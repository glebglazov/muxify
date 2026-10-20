#!/usr/bin/env python3
"""Ask Codex to edit its TOML while retaining the user's other settings."""

import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import time


def install_title(codex_home):
    config_path = codex_home / "config.toml"
    environment = dict(os.environ, CODEX_HOME=str(codex_home))
    environment.pop("TMUX", None)
    environment.pop("TMUX_PANE", None)
    process = subprocess.Popen(
        ["codex", "app-server", "--stdio"], cwd=codex_home, env=environment,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.monotonic() + 20
    buffer = b""
    request_id = 0

    def request(method, params):
        nonlocal buffer, request_id
        request_id += 1
        process.stdin.write((json.dumps({"id": request_id, "method": method, "params": params}) + "\n").encode())
        process.stdin.flush()
        while True:
            if b"\n" not in buffer:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([process.stdout], [], [], max(0, remaining))[0]:
                    raise RuntimeError("Codex config request timed out")
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError("Codex config server closed before its reply")
                buffer += chunk
                continue
            line, buffer = buffer.split(b"\n", 1)
            reply = json.loads(line)
            if reply.get("id") != request_id:
                continue
            if "error" in reply:
                raise RuntimeError(reply["error"].get("message", "Codex rejected the config change"))
            return reply["result"]

    try:
        request("initialize", {
            "clientInfo": {"name": "muxify_extension_install", "version": "1"},
            "capabilities": {"experimentalApi": True},
        })
        process.stdin.write(b'{"method":"initialized"}\n')
        process.stdin.flush()
        result = request("config/read", {"includeLayers": True})
        layer = next((layer for layer in result.get("layers") or []
                      if layer["name"]["type"] == "user"
                      and not layer["name"].get("profile")
                      and Path(layer["name"]["file"]).resolve() == config_path.resolve()), None)
        if layer is None:
            raise RuntimeError("Codex did not return its user config layer")
        existing = layer["config"].get("tui", {}).get("terminal_title")
        if existing is not None and (not isinstance(existing, list)
                                     or not all(isinstance(item, str) for item in existing)):
            raise RuntimeError("tui.terminal_title must be a list of strings")
        items = existing if existing is not None else ["activity", "thread-name", "project-name"]
        title = ["thread-id"] + [item for item in items if item not in ("thread-id", "session-id")]
        if existing == title:
            return
        if config_path.exists():
            shutil.copy2(config_path, str(config_path) + ".bak")
        request("config/value/write", {
            "keyPath": "tui.terminal_title", "value": title, "mergeStrategy": "replace",
            "filePath": str(config_path), "expectedVersion": layer["version"],
        })
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        process.stdout.close()


if __name__ == "__main__":
    try:
        install_title(Path(sys.argv[1]).resolve())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
