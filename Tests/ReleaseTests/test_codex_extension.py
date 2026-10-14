import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONVERSATION = "0199a3bf-aaf3-7bc0-9d16-4b6fbcab1a98"
OTHER = "0199a3bf-aaf3-7bc0-9d16-4b6fbcab1a99"


@unittest.skipUnless(shutil.which("jq"), "Codex Extension requires jq")
class CodexExtensionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="muxify-codex-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.home / "different-state"))
        for name in ("TMUX", "TMUX_PANE", "CODEX_HOME"):
            self.env.pop(name, None)
        self.reports = self.home / ".local/state/muxify/codex"

    def hook(self, event, conversation=CONVERSATION, **fields):
        result = subprocess.run(
            ["sh", str(ROOT / "extensions/codex/muxify-status.sh")],
            input=json.dumps(dict(hook_event_name=event, session_id=conversation, **fields)),
            text=True, capture_output=True, env=self.env, timeout=5,
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def report(self, conversation=CONVERSATION):
        return json.loads((self.reports / (conversation + ".json")).read_text())

    def test_reports_full_lifecycle_without_a_tmux_environment(self):
        for event, fields, expected in [
            ("SessionStart", {}, None),
            ("UserPromptSubmit", {}, "working"),
            ("PreToolUse", {"tool_name": "request_user_input"}, "blocked"),
            ("PreToolUse", {"tool_name": "exec_command"}, "working"),
            ("PermissionRequest", {}, "blocked"),
            ("PostToolUse", {}, "working"),
            ("Stop", {}, "done"),
            ("UserPromptSubmit", {}, "working"),
            ("Interrupt", {}, "done"),
            ("SessionEnd", {}, None),
        ]:
            with self.subTest(event=event, fields=fields):
                self.hook(event, **fields)
                self.assertEqual(self.report(), {"version": 1, "conversation": CONVERSATION, "status": expected})
        self.assertFalse((self.home / "different-state").exists())
        self.assertEqual((self.reports / (CONVERSATION + ".json")).stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.reports.glob(".report.*")), [])

    def test_start_clears_previous_status_and_end_keeps_identity_for_other_tuis(self):
        self.hook("Stop")
        self.hook("SessionStart")
        self.assertIsNone(self.report()["status"])
        self.hook("UserPromptSubmit", OTHER)
        self.hook("SessionEnd")
        self.assertIsNone(self.report()["status"])
        self.assertEqual(self.report(OTHER)["status"], "working")

    def test_invalid_input_and_subagents_cannot_change_reports(self):
        self.hook("Stop", CONVERSATION.upper())
        original = self.report()
        self.hook("UserPromptSubmit", agent_id="child")
        self.hook("Unknown")
        for bad in ("../../outside", "", CONVERSATION + "\n", None, 7):
            self.hook("UserPromptSubmit", bad)
        for payload in ("not JSON", "{}{}", "[]", "null"):
            result = subprocess.run(["sh", str(ROOT / "extensions/codex/muxify-status.sh")],
                                    input=payload, text=True, capture_output=True, env=self.env, timeout=5)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
        self.assertEqual(self.report(), original)
        self.assertEqual(len(list(self.reports.iterdir())), 1)

    @unittest.skipUnless(shutil.which("codex") and shutil.which("python3"), "Installer requires Codex and Python 3")
    def test_installer_preserves_config_and_hooks_and_is_idempotent(self):
        codex_home = self.home / ".codex"
        codex_home.mkdir()
        config = codex_home / "config.toml"
        original = '# User comment\nmodel = "gpt-5"\n[tui]\nterminal_title = ["project-name", "session-id", "thread-id", "activity"]\n'
        config.write_text(original)
        hooks = codex_home / "hooks.json"
        hooks.write_text(json.dumps({"custom": True, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo existing"}]}]}}))
        for index in range(2):
            result = subprocess.run(["sh", str(ROOT / "extensions/install.sh")], env=self.env,
                                    text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("codex: " + ("installed" if index == 0 else "updated"), result.stdout)
            self.assertNotIn("--no-daemon", result.stdout)
            updated = config.read_text()
            self.assertIn('# User comment\nmodel = "gpt-5"', updated)
            self.assertIn('terminal_title = ["thread-id", "project-name", "activity"]', updated)
            self.assertEqual((codex_home / "config.toml.bak").read_text(), original)
            if index == 0:
                first = config.read_bytes(), hooks.read_bytes(), config.stat().st_mtime_ns, hooks.stat().st_mtime_ns
            else:
                self.assertEqual(first, (config.read_bytes(), hooks.read_bytes(), config.stat().st_mtime_ns, hooks.stat().st_mtime_ns))
        registered = json.loads(hooks.read_text())
        self.assertTrue(registered["custom"])
        self.assertEqual(registered["hooks"]["Stop"][0]["hooks"][0]["command"], "echo existing")
        self.assertEqual(registered["hooks"]["Stop"][1]["hooks"][0]["command"], 'sh "$HOME/.codex/muxify-status.sh"')

    @unittest.skipUnless(shutil.which("codex") and shutil.which("python3"), "Installer requires Codex and Python 3")
    def test_custom_home_and_title_defaults_use_native_codex_config_writer(self):
        codex_home = self.home / 'custom codex $name "quoted"'
        codex_home.mkdir()
        self.env["CODEX_HOME"] = str(codex_home)
        for existing, expected in [(None, '["thread-id", "activity", "thread-name", "project-name"]'), ("[]", '["thread-id"]')]:
            with self.subTest(existing=existing):
                config = codex_home / "config.toml"
                if existing is None:
                    config.unlink(missing_ok=True)
                else:
                    config.write_text('[tui]\nterminal_title = ' + existing + '\n')
                result = subprocess.run(["sh", str(ROOT / "extensions/install.sh")], env=self.env,
                                        text=True, capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                self.assertIn('terminal_title = ' + expected, config.read_text())
                command = json.loads((codex_home / "hooks.json").read_text())["hooks"]["Stop"][0]["hooks"][0]["command"]
                for shell in ["sh", "zsh", "fish"]:
                    if shutil.which(shell):
                        result = subprocess.run([shell, "-c", command], input=json.dumps({"hook_event_name": "Stop", "session_id": CONVERSATION}),
                                                text=True, capture_output=True, env=self.env, timeout=5)
                        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""), shell)
                self.assertEqual(self.report()["status"], "done")
        self.assertFalse((self.home / ".codex/hooks.json").exists())

    def test_missing_dependency_leaves_codex_setup_unchanged(self):
        codex_home = self.home / ".codex"
        codex_home.mkdir()
        config = codex_home / "config.toml"
        config.write_text('# untouched\n')
        tools = self.home / "tools"
        tools.mkdir()
        for name in ("dirname", "jq", "python3"):
            if shutil.which(name):
                (tools / name).symlink_to(shutil.which(name))
        self.env["PATH"] = str(tools)
        result = subprocess.run(["/bin/sh", str(ROOT / "extensions/install.sh")], env=self.env,
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertIn("codex: failed (codex not found)", result.stdout)
        self.assertEqual(config.read_text(), '# untouched\n')
        self.assertEqual(list(codex_home.iterdir()), [config])

    @unittest.skipUnless(shutil.which("codex") and shutil.which("python3"), "Installer requires Codex and Python 3")
    def test_invalid_config_is_reported_without_installing_hooks(self):
        codex_home = self.home / ".codex"
        codex_home.mkdir()
        config = codex_home / "config.toml"
        config.write_text('[tui]\nterminal_title = 123\n')
        result = subprocess.run(["sh", str(ROOT / "extensions/install.sh")], env=self.env,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 1)
        self.assertIn("codex: failed", result.stdout)
        self.assertEqual(config.read_text(), '[tui]\nterminal_title = 123\n')
        self.assertFalse((codex_home / "config.toml.bak").exists())
        self.assertFalse((codex_home / "hooks.json").exists())
        self.assertFalse((codex_home / "muxify-status.sh").exists())


if __name__ == "__main__":
    unittest.main()
