#!/bin/sh
# Tests the Extensions and the installer without any Agent installed.
#
#   sh extensions/test.sh
#
# A fake tmux (prepended to PATH) appends each invocation's arguments as one
# line to a log, and TMUX_PANE is a fake Pane id, so each case feeds an
# Extension an Agent event and asserts the tmux calls it made. Installer cases
# run against a temporary HOME; the real HOME is never touched. Stops at the
# first mismatch, naming the case, and exits non-zero. Needs jq, and node 24
# for the OpenCode plugin and the Pi extension, which small Node scripts drive
# with a fake api and a fake pi (Node runs the Pi .ts file by stripping types).
#
# Each Agent adds a <agent>_hook_cases and an <agent>_install_cases function
# and lists them at the bottom.

set -u

ext=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/muxify-extensions-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM

mkdir "$work/bin"
cat >"$work/bin/tmux" <<'TMUX'
#!/bin/sh
printf '%s\n' "$*" >>"$TMUX_LOG"
if [ -n "${FAKE_TMUX_FAIL:-}" ]; then
	echo "fake tmux: no server running" >&2
	exit 1
fi
TMUX
chmod 755 "$work/bin/tmux"

PATH=$work/bin:$PATH
TMUX_LOG=$work/tmux.log
TMUX_PANE=%99
HOME=$work/no-home # each installer case makes its own
unset FAKE_TMUX_FAIL
export PATH TMUX_LOG TMUX_PANE HOME

case_name=
passed=0

begin() {
	case_name=$1
	: >"$TMUX_LOG"
}

fail() {
	printf 'FAIL: %s\n' "$case_name" >&2
	printf '%s\n' "$@" >&2
	exit 1
}

pass() {
	passed=$((passed + 1))
}

# run_hook <script> <json>: feeds one event on stdin; the script must exit 0
# and print nothing.
run_hook() {
	hook_out=$(printf '%s' "$2" | sh "$1" 2>&1)
	hook_rc=$?
	[ "$hook_rc" -eq 0 ] || fail "exited $hook_rc"
	[ -z "$hook_out" ] || fail "printed: $hook_out"
}

# expect_tmux [line...]: the fake tmux log holds exactly these invocations
# (none when no argument is given).
expect_tmux() {
	if [ $# -eq 0 ]; then expected=; else expected=$(printf '%s\n' "$@"); fi
	actual=$(cat "$TMUX_LOG")
	[ "$actual" = "$expected" ] ||
		fail "expected tmux calls:" "${expected:-(none)}" "got:" "${actual:-(none)}"
	pass
}

# new_home: a fresh, empty temporary HOME.
home_count=0
new_home() {
	home_count=$((home_count + 1))
	HOME=$work/home$home_count
	mkdir "$HOME"
}

# run_install: runs the installer against $HOME; output in $install_out.
run_install() {
	install_out=$(sh "$ext/install.sh" 2>&1)
	install_rc=$?
}

# expect_install_line <agent> <line>: the installer printed exactly one line
# for <agent>, and it is <line>.
expect_install_line() {
	count=$(printf '%s\n' "$install_out" | grep -c "^$1: ")
	[ "$count" -eq 1 ] || fail "expected one '$1:' line, got $count:" "$install_out"
	printf '%s\n' "$install_out" | grep -qxF "$2" || fail "expected '$2', got:" "$install_out"
}

# expect_json <file> <jq expression>: the expression is true for the file.
expect_json() {
	jq -e "$2" "$1" >/dev/null || fail "expected $2 in $1:" "$(cat "$1")"
}

expect_same_file() {
	cmp -s "$1" "$2" || fail "expected $2 to equal $1"
}

# --- Claude Code ------------------------------------------------------------

claude_hook=$ext/claude/muxify-status.sh
claude_agent='set -p -t %99 @muxify_agent claude'

claude_status() {
	printf '%s\n' "set -p -t %99 @muxify_agent claude ; set -p -t %99 @muxify_agent_status $1"
}

# claude_case <event> <status> [extra JSON fields]
claude_case() {
	begin "claude: $1${3:+ ($3)} -> $2"
	run_hook "$claude_hook" "{\"session_id\":\"s1\",\"hook_event_name\":\"$1\"${3:+,$3}}"
	expect_tmux "$(claude_status "$2")"
}

claude_hook_cases() {
	begin "claude: SessionStart names the Agent only"
	run_hook "$claude_hook" '{"session_id":"s1","hook_event_name":"SessionStart","source":"startup"}'
	expect_tmux "$claude_agent"

	claude_case UserPromptSubmit working '"prompt":"hi"'
	claude_case PostToolUse working '"tool_name":"Bash"'
	claude_case ElicitationResult working '"mcp_server_name":"srv"'
	claude_case PermissionRequest blocked '"tool_name":"Bash"'
	claude_case Elicitation blocked '"mcp_server_name":"srv"'
	claude_case PreToolUse blocked '"tool_name":"AskUserQuestion"'
	claude_case PreToolUse blocked '"tool_name":"ExitPlanMode"'
	claude_case Stop done '"stop_hook_active":false'
	claude_case StopFailure failed '"error":"api_error"'

	begin "claude: SessionEnd unsets both options"
	run_hook "$claude_hook" '{"session_id":"s1","hook_event_name":"SessionEnd","reason":"exit"}'
	expect_tmux 'set -p -u -t %99 @muxify_agent ; set -p -u -t %99 @muxify_agent_status'

	for event in PostToolUse PermissionRequest PreToolUse Stop; do
		begin "claude: subagent $event writes nothing"
		run_hook "$claude_hook" "{\"session_id\":\"s1\",\"hook_event_name\":\"$event\",\"agent_id\":\"a1\",\"agent_type\":\"Explore\",\"tool_name\":\"AskUserQuestion\"}"
		expect_tmux
	done

	for event in Notification SubagentStop PreCompact Bogus; do
		begin "claude: unknown event $event writes nothing"
		run_hook "$claude_hook" "{\"session_id\":\"s1\",\"hook_event_name\":\"$event\"}"
		expect_tmux
	done

	begin "claude: payload without hook_event_name writes nothing"
	run_hook "$claude_hook" '{"session_id":"s1"}'
	expect_tmux

	begin "claude: invalid JSON writes nothing"
	run_hook "$claude_hook" 'not json'
	expect_tmux

	begin "claude: TMUX_PANE unset writes nothing"
	(
		unset TMUX_PANE
		run_hook "$claude_hook" '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}'
	) || exit 1
	expect_tmux

	begin "claude: empty TMUX_PANE writes nothing"
	TMUX_PANE= run_hook "$claude_hook" '{"session_id":"s1","hook_event_name":"Stop"}'
	TMUX_PANE=%99
	expect_tmux

	begin "claude: a failing tmux still exits 0 silently"
	FAKE_TMUX_FAIL=1 run_hook "$claude_hook" '{"session_id":"s1","hook_event_name":"Stop"}'
	unset FAKE_TMUX_FAIL
	expect_tmux "$(claude_status done)"
}

claude_command='sh "$HOME/.claude/hooks/muxify-status.sh"'
claude_events='SessionStart UserPromptSubmit PreToolUse PermissionRequest PostToolUse Elicitation ElicitationResult Stop StopFailure SessionEnd'

claude_install_cases() {
	# A settings.json in the user's own formatting, with foreign hooks and keys.
	new_home
	mkdir "$HOME/.claude"
	settings=$HOME/.claude/settings.json
	cat >"$settings" <<'JSON'
{
    "model": "opus",
    "permissions": { "allow": ["Bash(ls:*)"] },
    "hooks": {
        "Stop": [
            { "hooks": [ { "type": "command", "command": "echo other" } ] }
        ],
        "PreToolUse": [
            { "hooks": [ { "type": "command", "command": "echo raycast" } ] }
        ]
    },
    "theme": "dark"
}
JSON
	cp "$settings" "$work/original.json"

	begin "claude install: first run says installed"
	run_install
	expect_install_line claude "claude: installed"
	[ "$install_rc" -eq 0 ] || fail "installer exited $install_rc:" "$install_out"
	pass

	begin "claude install: copies the hook script, executable, not a symlink"
	script=$HOME/.claude/hooks/muxify-status.sh
	[ -f "$script" ] && [ ! -L "$script" ] || fail "missing or a symlink: $script"
	[ -x "$script" ] || fail "not executable: $script"
	expect_same_file "$claude_hook" "$script"
	pass

	begin "claude install: backs settings.json up to settings.json.bak"
	expect_same_file "$work/original.json" "$settings.bak"
	pass

	begin "claude install: adds one synchronous entry per event"
	for event in $claude_events; do
		jq -e --arg e "$event" --arg cmd "$claude_command" '
			[.hooks[$e][] | select(any(.hooks[]; .command == $cmd))]
			| length == 1
			and (.[0].hooks == [{type: "command", command: $cmd, timeout: 5}])' \
			"$settings" >/dev/null || fail "no single Muxify entry for $event:" "$(cat "$settings")"
	done
	pass

	begin "claude install: PreToolUse entry has the AskUserQuestion|ExitPlanMode matcher"
	expect_json "$settings" '.hooks.PreToolUse[-1].matcher == "AskUserQuestion|ExitPlanMode"'
	pass

	begin "claude install: other events get no matcher"
	expect_json "$settings" '[.hooks | to_entries[] | select(.key != "PreToolUse") | .value[-1] | has("matcher")] | any | not'
	pass

	begin "claude install: foreign hooks and other keys are untouched"
	jq -e --slurpfile old "$work/original.json" '
		$old[0] as $o
		| .hooks.Stop[0] == $o.hooks.Stop[0]
		and .hooks.PreToolUse[0] == $o.hooks.PreToolUse[0]
		and (.hooks.Stop | length) == 2
		and (.hooks.PreToolUse | length) == 2
		and (del(.hooks) == ($o | del(.hooks)))
		and (keys_unsorted == ($o | keys_unsorted))' "$settings" >/dev/null ||
		fail "foreign entries or keys changed:" "$(cat "$settings")"
	pass

	begin "claude install: the registered command runs the installed hook"
	: >"$TMUX_LOG"
	printf '%s' '{"hook_event_name":"Stop"}' | sh -c "$claude_command"
	expect_tmux "$(claude_status done)"

	begin "claude install: second run says updated and leaves settings.json byte-identical"
	cp "$settings" "$work/after-first.json"
	run_install
	expect_install_line claude "claude: updated"
	expect_same_file "$work/after-first.json" "$settings"
	expect_same_file "$work/original.json" "$settings.bak"
	pass

	begin "claude install: an updated hook script is copied again"
	echo '# stale' >"$script"
	run_install
	expect_install_line claude "claude: updated"
	expect_same_file "$claude_hook" "$script"
	pass

	begin "claude install: without jq prints failed and changes nothing"
	new_home
	mkdir "$HOME/.claude" "$work/nojq-bin"
	echo '{}' >"$HOME/.claude/settings.json"
	ln -s "$(command -v dirname)" "$work/nojq-bin/dirname"
	install_out=$(PATH=$work/nojq-bin /bin/sh "$ext/install.sh" 2>&1)
	expect_install_line claude "claude: failed (jq not found)"
	[ "$(find "$HOME" -mindepth 1 | sort)" = "$(printf '%s\n' "$HOME/.claude" "$HOME/.claude/settings.json")" ] ||
		fail "changed:" "$(find "$HOME" -mindepth 1)"
	[ "$(cat "$HOME/.claude/settings.json")" = '{}' ] || fail "settings.json changed"
	pass

	begin "claude install: no .claude directory prints not found and creates nothing"
	new_home
	run_install
	expect_install_line claude "claude: not found"
	[ -z "$(find "$HOME" -mindepth 1)" ] || fail "created:" "$(find "$HOME" -mindepth 1)"
	pass

	begin "claude install: missing settings.json is created without a backup"
	new_home
	mkdir "$HOME/.claude"
	run_install
	expect_install_line claude "claude: installed"
	settings=$HOME/.claude/settings.json
	expect_json "$settings" '(.hooks | keys | length) == 10 and (del(.hooks) == {})'
	[ ! -e "$settings.bak" ] || fail "unexpected backup: $settings.bak"
	pass

	begin "claude install: a settings.json that already has every entry is not rewritten"
	cp "$settings" "$work/complete.json"
	rm "$HOME/.claude/hooks/muxify-status.sh"
	run_install
	expect_install_line claude "claude: installed"
	expect_same_file "$work/complete.json" "$settings"
	[ ! -e "$settings.bak" ] || fail "unexpected backup: $settings.bak"
	pass
}

# --- Codex CLI --------------------------------------------------------------

codex_hook=$ext/codex/muxify-status.sh
codex_agent='set -p -t %99 @muxify_agent codex'
codex_unset='set -p -u -t %99 @muxify_agent ; set -p -u -t %99 @muxify_agent_status'

codex_status() {
	printf '%s\n' "set -p -t %99 @muxify_agent codex ; set -p -t %99 @muxify_agent_status $1"
}

# codex_event <event> [extra JSON fields]: a Codex hook payload.
codex_event() {
	printf '%s\n' "{\"session_id\":\"s1\",\"turn_id\":\"t1\",\"hook_event_name\":\"$1\"${2:+,$2}}"
}

# codex_case <event> <status> [extra JSON fields]
codex_case() {
	begin "codex: $1${3:+ ($3)} -> $2"
	run_hook "$codex_hook" "$(codex_event "$1" "${3:-}")"
	expect_tmux "$(codex_status "$2")"
}

# run_hook_under <json> <arg...>: like run_hook, but the hook runs as a child
# of a shell whose arguments end in <arg...>, as when Codex's daemon runs it
# through the user's login shell. The trailing exit keeps the shell from
# exec'ing the hook in its own place.
run_hook_under() {
	hook_json=$1
	shift
	hook_out=$(printf '%s' "$hook_json" | sh -c 'sh "$0"; exit' "$codex_hook" "$@" 2>&1)
	hook_rc=$?
	[ "$hook_rc" -eq 0 ] || fail "exited $hook_rc"
	[ -z "$hook_out" ] || fail "printed: $hook_out"
}

codex_hook_cases() {
	# The daemon guard checks every ancestor of the hook, and those include this
	# suite's own ancestors, so none of them may carry the daemon marker (they
	# do when the suite runs inside Codex's shared daemon).
	begin "codex: the suite does not run under a process mentioning the daemon marker"
	pid=$$
	while [ "${pid:-1}" -gt 1 ]; do
		info=$(ps -ww -o ppid= -o args= -p "$pid" 2>/dev/null) || break
		case $info in *--managed-daemon*) fail "process $pid's arguments contain the marker; run the suite elsewhere:" "$info" ;; esac
		set -- $info
		pid=$1
	done
	pass

	begin "codex: SessionStart names the Agent only"
	run_hook "$codex_hook" "$(codex_event SessionStart '"source":"startup","model":"gpt-5.5"')"
	expect_tmux "$codex_agent"

	codex_case UserPromptSubmit working '"prompt":"hi"'
	codex_case PreToolUse working '"tool_name":"shell","tool_input":{"command":["ls"]}'
	codex_case PreToolUse working '"tool_name":"apply_patch"'
	codex_case PreToolUse blocked '"tool_name":"request_user_input"'
	codex_case PostToolUse working '"tool_name":"shell","tool_response":"ok"'
	codex_case PostToolUse working '"tool_name":"request_user_input"'
	codex_case PermissionRequest blocked '"tool_name":"shell"'
	codex_case Stop done '"stop_hook_active":false'
	codex_case Interrupt done

	begin "codex: SessionEnd unsets both options"
	run_hook "$codex_hook" "$(codex_event SessionEnd '"reason":"exit"')"
	expect_tmux "$codex_unset"

	for event in UserPromptSubmit PreToolUse PostToolUse PermissionRequest; do
		begin "codex: subagent $event writes nothing"
		run_hook "$codex_hook" "$(codex_event "$event" '"agent_id":"a1","tool_name":"request_user_input"')"
		expect_tmux
	done

	begin "codex: a null agent_id counts as the main conversation"
	run_hook "$codex_hook" "$(codex_event PermissionRequest '"agent_id":null,"tool_name":"shell"')"
	expect_tmux "$(codex_status blocked)"

	for event in Notification SubagentStop PreCompact Bogus; do
		begin "codex: unknown event $event writes nothing"
		run_hook "$codex_hook" "$(codex_event "$event")"
		expect_tmux
	done

	begin "codex: payload without hook_event_name writes nothing"
	run_hook "$codex_hook" '{"session_id":"s1"}'
	expect_tmux

	begin "codex: invalid JSON writes nothing"
	run_hook "$codex_hook" 'not json'
	expect_tmux

	begin "codex: TMUX_PANE unset writes nothing"
	(
		unset TMUX_PANE
		run_hook "$codex_hook" "$(codex_event UserPromptSubmit)"
	) || exit 1
	expect_tmux

	begin "codex: empty TMUX_PANE writes nothing"
	TMUX_PANE= run_hook "$codex_hook" "$(codex_event Stop)"
	TMUX_PANE=%99
	expect_tmux

	begin "codex: a failing tmux still exits 0 silently"
	FAKE_TMUX_FAIL=1 run_hook "$codex_hook" "$(codex_event Stop)"
	unset FAKE_TMUX_FAIL
	expect_tmux "$(codex_status done)"

	begin "codex: run by a parent that is not the daemon, it still reports"
	run_hook_under "$(codex_event UserPromptSubmit)" app-server --listen unix://
	expect_tmux "$(codex_status working)"

	begin "codex: run by the managed daemon, it writes nothing"
	for event in SessionStart UserPromptSubmit PermissionRequest Stop SessionEnd; do
		run_hook_under "$(codex_event "$event")" app-server --listen unix:// --managed-daemon
	done
	expect_tmux

	begin "codex: the daemon two levels up (through a login shell) still writes nothing"
	hook_out=$(codex_event Stop | sh -c 'sh -c "sh \"\$0\"; exit" "$0"; exit' "$codex_hook" app-server --managed-daemon 2>&1)
	[ $? -eq 0 ] && [ -z "$hook_out" ] || fail "exited non-zero or printed: $hook_out"
	expect_tmux

	# Codex writes the payload while the hook runs; a hook leaving early must
	# not make that write fail on a closed pipe.
	begin "codex: the daemon guard reads a large payload to the end"
	big=$(head -c 200000 /dev/zero | tr '\0' x)
	rm -f "$work/writer-rc"
	{
		codex_event PostToolUse "\"tool_response\":\"$big\""
		echo $? >"$work/writer-rc"
	} | sh -c 'sh "$0"; exit' "$codex_hook" --managed-daemon
	[ "$(cat "$work/writer-rc" 2>/dev/null)" = 0 ] || fail "writing the payload failed: the hook closed stdin early"
	expect_tmux
}

codex_command='sh "$HOME/.codex/muxify-status.sh"'
codex_events='SessionStart UserPromptSubmit PreToolUse PermissionRequest PostToolUse Stop Interrupt SessionEnd'
codex_trust_reminder='  Trust the new hooks once: run /hooks in Codex and approve them.'
codex_daemon_reminder="  Launch Codex with codex --no-daemon (fish: alias codex 'command codex --no-daemon'), or it can't report its Status."

# expect_codex_reminders: the installer printed both Codex reminders, right
# after the codex: line.
expect_codex_reminders() {
	printf '%s\n' "$install_out" | grep -A2 '^codex: ' | sed 1d >"$work/reminders"
	printf '%s\n' "$codex_trust_reminder" "$codex_daemon_reminder" >"$work/reminders.expected"
	cmp -s "$work/reminders.expected" "$work/reminders" ||
		fail "expected the Codex reminders after the codex: line, got:" "$install_out"
}

codex_install_cases() {
	# A hooks.json like the user's, with herdr and lavish SessionStart hooks.
	new_home
	mkdir "$HOME/.codex"
	codex_hooks=$HOME/.codex/hooks.json
	cat >"$codex_hooks" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "command": "lavish-axi", "timeout": 10, "type": "command" }
        ],
        "matcher": ""
      },
      {
        "hooks": [
          { "command": "bash '/Users/someone/.codex/herdr-agent-state.sh' session", "timeout": 10, "type": "command" }
        ]
      }
    ]
  },
  "extra": true
}
JSON
	cp "$codex_hooks" "$work/codex-original.json"
	echo 'model = "gpt-5.5"' >"$HOME/.codex/config.toml"

	begin "codex install: first run says installed and prints both reminders"
	run_install
	expect_install_line codex "codex: installed"
	[ "$install_rc" -eq 0 ] || fail "installer exited $install_rc:" "$install_out"
	expect_codex_reminders
	pass

	begin "codex install: copies the hook script, executable, not a symlink"
	codex_script=$HOME/.codex/muxify-status.sh
	[ -f "$codex_script" ] && [ ! -L "$codex_script" ] || fail "missing or a symlink: $codex_script"
	[ -x "$codex_script" ] || fail "not executable: $codex_script"
	expect_same_file "$codex_hook" "$codex_script"
	pass

	begin "codex install: backs hooks.json up to hooks.json.bak"
	expect_same_file "$work/codex-original.json" "$codex_hooks.bak"
	pass

	begin "codex install: adds one synchronous entry without matcher per event"
	for event in $codex_events; do
		jq -e --arg e "$event" --arg cmd "$codex_command" '
			[.hooks[$e][] | select(any(.hooks[]; .command == $cmd))]
			| length == 1
			and (.[0] == {hooks: [{type: "command", command: $cmd, timeout: 5}]})' \
			"$codex_hooks" >/dev/null || fail "no single Muxify entry for $event:" "$(cat "$codex_hooks")"
	done
	expect_json "$codex_hooks" '(.hooks | keys | length) == 8'
	pass

	begin "codex install: the foreign SessionStart hooks and other keys are untouched"
	jq -e --slurpfile old "$work/codex-original.json" '
		$old[0] as $o
		| .hooks.SessionStart[0:2] == $o.hooks.SessionStart
		and (.hooks.SessionStart | length) == 3
		and (del(.hooks) == ($o | del(.hooks)))' "$codex_hooks" >/dev/null ||
		fail "foreign entries or keys changed:" "$(cat "$codex_hooks")"
	[ "$(cat "$HOME/.codex/config.toml")" = 'model = "gpt-5.5"' ] || fail "config.toml changed"
	pass

	begin "codex install: the registered command runs the installed hook"
	: >"$TMUX_LOG"
	codex_event PermissionRequest | sh -c "$codex_command"
	expect_tmux "$(codex_status blocked)"

	begin "codex install: second run says updated, reminds again and leaves hooks.json byte-identical"
	cp "$codex_hooks" "$work/codex-after-first.json"
	run_install
	expect_install_line codex "codex: updated"
	expect_codex_reminders
	expect_same_file "$work/codex-after-first.json" "$codex_hooks"
	expect_same_file "$work/codex-original.json" "$codex_hooks.bak"
	pass

	begin "codex install: an updated hook script is copied again, a symlink replaced"
	echo '# stale' >"$work/codex-target.sh"
	rm "$codex_script"
	ln -s "$work/codex-target.sh" "$codex_script"
	run_install
	expect_install_line codex "codex: updated"
	[ -f "$codex_script" ] && [ ! -L "$codex_script" ] || fail "still a symlink: $codex_script"
	expect_same_file "$codex_hook" "$codex_script"
	[ "$(cat "$work/codex-target.sh")" = '# stale' ] || fail "the symlink's target changed"
	pass

	begin "codex install: without jq prints failed, no reminders, and changes nothing"
	new_home
	mkdir "$HOME/.codex"
	mkdir -p "$work/nojq-bin"
	[ -e "$work/nojq-bin/dirname" ] || ln -s "$(command -v dirname)" "$work/nojq-bin/dirname"
	echo '{"hooks":{}}' >"$HOME/.codex/hooks.json"
	install_out=$(PATH=$work/nojq-bin /bin/sh "$ext/install.sh" 2>&1)
	expect_install_line codex "codex: failed (jq not found)"
	! printf '%s\n' "$install_out" | grep -q -e '/hooks' -e '--no-daemon' || fail "reminders printed:" "$install_out"
	[ "$(find "$HOME" -mindepth 1 | sort)" = "$(printf '%s\n' "$HOME/.codex" "$HOME/.codex/hooks.json")" ] ||
		fail "changed:" "$(find "$HOME" -mindepth 1)"
	pass

	begin "codex install: no .codex directory prints not found, no reminders, and creates nothing"
	new_home
	run_install
	expect_install_line codex "codex: not found"
	! printf '%s\n' "$install_out" | grep -q -e '/hooks' -e '--no-daemon' || fail "reminders printed:" "$install_out"
	[ -z "$(find "$HOME" -mindepth 1)" ] || fail "created:" "$(find "$HOME" -mindepth 1)"
	pass

	begin "codex install: missing hooks.json is created without a backup"
	new_home
	mkdir "$HOME/.codex"
	run_install
	expect_install_line codex "codex: installed"
	codex_hooks=$HOME/.codex/hooks.json
	expect_json "$codex_hooks" '(.hooks | keys | length) == 8 and (del(.hooks) == {})'
	[ ! -e "$codex_hooks.bak" ] || fail "unexpected backup: $codex_hooks.bak"
	pass

	begin "codex install: a hooks.json that already has every entry is not rewritten"
	cp "$codex_hooks" "$work/codex-complete.json"
	rm "$HOME/.codex/muxify-status.sh"
	run_install
	expect_install_line codex "codex: installed"
	expect_same_file "$work/codex-complete.json" "$codex_hooks"
	[ ! -e "$codex_hooks.bak" ] || fail "unexpected backup: $codex_hooks.bak"
	pass
}

# --- OpenCode 2 -------------------------------------------------------------

opencode_plugin=$ext/opencode/muxify-status/tui.js
opencode_driver=$work/opencode-driver.mjs
opencode_agent='set -p -t %99 @muxify_agent opencode'
opencode_unset='set -p -u -t %99 @muxify_agent ; set -p -u -t %99 @muxify_agent_status'

# A fake OpenCode 2 TUI: loads the plugin, calls setup with a fake api and
# feeds it the steps given as arguments, in order. The server holds two session
# trees: root > child > grandchild, open in this TUI, and other > other-child.
#   <event type>:<session>[:<id>]  an event from that session; <id> is the
#                                   request, form or (session.created) parent id
#   route:<session> | route:home    what the TUI shows from now on
#   cleanup                         calls the cleanup setup returned
# Events are delivered even after cleanup, like a late one would be. The
# process then exits normally.
cat >"$opencode_driver" <<'JS'
import { pathToFileURL } from "node:url";

const [plugin, ...steps] = process.argv.slice(2);
const { default: extension } = await import(pathToFileURL(plugin).href);
if (extension?.id !== "muxify.agent-status" || typeof extension.setup !== "function") {
	console.error("default export is not { id: \"muxify.agent-status\", setup }");
	process.exit(2);
}

const sessions = new Map([
	["root", { id: "root" }],
	["child", { id: "child", parentID: "root" }],
	["grandchild", { id: "grandchild", parentID: "child" }],
	["other", { id: "other" }],
	["other-child", { id: "other-child", parentID: "other" }],
]);
let route = { type: "session", sessionID: "root" };
let listener;
let subscribed = false;

const api = {
	data: {
		listen(handler) {
			listener = handler;
			subscribed = true;
			return () => {
				subscribed = false;
			};
		},
		session: { get: (id) => sessions.get(id) },
	},
	ui: { router: { current: () => route } },
};

function payload(type, sessionID, id) {
	switch (type) {
		case "permission.asked":
			return { id, sessionID, action: "bash", resources: ["ls"] };
		case "permission.replied":
			return { sessionID, requestID: id, reply: "once" };
		case "form.created":
			return { form: { id, sessionID, fields: [] } };
		case "form.replied":
			return { id, sessionID, answer: {} };
		case "session.created":
			return { sessionID, parentID: id, projectID: "p", slug: sessionID };
		case "session.execution.interrupted":
			return { sessionID, reason: "user" };
		case "session.execution.failed":
			return { sessionID, error: { type: "unknown", message: "boom" } };
		default:
			return { sessionID, id };
	}
}

const cleanup = extension.setup(api);
for (const step of steps) {
	const [type, session, id] = step.split(":");
	if (type === "route") {
		route = session === "home" ? { type: "home" } : { type: "session", sessionID: session };
	} else if (type === "cleanup") {
		await cleanup?.();
		if (subscribed) {
			console.error("cleanup left the event listener subscribed");
			process.exit(2);
		}
	} else {
		listener?.({ details: { type, data: payload(type, session, id) } });
	}
}
JS

# opencode_status <status>: the tmux call that publishes <status>; "none"
# unsets the Status and keeps the Agent.
opencode_status() {
	if [ "$1" = none ]; then
		printf '%s\n' "set -p -t %99 @muxify_agent opencode ; set -p -u -t %99 @muxify_agent_status"
	else
		printf '%s\n' "set -p -t %99 @muxify_agent opencode ; set -p -t %99 @muxify_agent_status $1"
	fi
}

# run_opencode <plugin> [step...]: the fake TUI must exit 0 and print nothing.
run_opencode() {
	opencode_out=$(node "$opencode_driver" "$@" 2>&1)
	opencode_rc=$?
	[ "$opencode_rc" -eq 0 ] || fail "exited $opencode_rc:" "$opencode_out"
	[ -z "$opencode_out" ] || fail "printed: $opencode_out"
}

# opencode_case <name> <steps> <statuses>: runs the space-separated steps and
# expects setup to name the Agent, then one write per status, then the unset
# of both options when the process exits.
opencode_case() {
	begin "opencode: $1"
	# shellcheck disable=SC2086 # steps are split on purpose
	run_opencode "$opencode_plugin" $2
	opencode_statuses=$3
	set -- "$opencode_agent"
	for status in $opencode_statuses; do
		set -- "$@" "$(opencode_status "$status")"
	done
	expect_tmux "$@" "$opencode_unset"
}

opencode_hook_cases() {
	started=session.execution.started:root
	succeeded=session.execution.succeeded:root
	interrupted=session.execution.interrupted:root
	failed=session.execution.failed:root

	opencode_case "setup names the Agent only; exit unsets both" "" ""
	opencode_case "started -> working" "$started" "working"
	opencode_case "succeeded -> done" "$started $succeeded" "working done"
	opencode_case "interrupted (Esc) -> done" "$started $interrupted" "working done"
	opencode_case "failed -> failed" "$started $failed" "working failed"
	opencode_case "a new execution after done -> working" "$started $succeeded $started" "working done working"
	opencode_case "a repeated Status is written once" "$started $started" "working"

	opencode_case "permission asked -> blocked, replied -> working, succeeded -> done" \
		"$started permission.asked:root:p1 permission.replied:root:p1 $succeeded" \
		"working blocked working done"
	opencode_case "form created -> blocked, replied -> working" \
		"$started form.created:root:f1 form.replied:root:f1" "working blocked working"
	opencode_case "form cancelled -> working" \
		"$started form.created:root:f1 form.cancelled:root:f1" "working blocked working"
	opencode_case "stays blocked while any permission or form is pending" \
		"$started permission.asked:root:p1 form.created:root:f1 permission.replied:root:p1 form.replied:root:f1" \
		"working blocked working"
	opencode_case "an execution ending under a pending blocker shows once it is answered" \
		"$started permission.asked:root:p1 $failed permission.replied:root:p1" "working blocked failed"
	opencode_case "a reply to an unknown request changes nothing" \
		"$started permission.replied:root:x form.cancelled:root:x form.replied:root:x" "working"
	opencode_case "a blocker answered before any execution leaves no Status" \
		"permission.asked:root:p1 permission.replied:root:p1" "blocked none"

	opencode_case "a child session's permission blocks" \
		"$started permission.asked:child:p1 permission.replied:child:p1" "working blocked working"
	opencode_case "a grandchild session's form blocks" \
		"$started form.created:grandchild:f1 form.cancelled:grandchild:f1" "working blocked working"
	opencode_case "subagent executions don't drive the Status" \
		"$started session.execution.succeeded:child session.execution.failed:grandchild $succeeded session.execution.started:child" \
		"working done"
	opencode_case "a subagent announced by session.created is followed" \
		"$started session.created:late:child permission.asked:late:p1" "working blocked"
	opencode_case "an unrelated session's events write nothing" \
		"session.execution.started:other permission.asked:other:p1 form.created:other-child:f1 session.execution.failed:other session.execution.succeeded:other-child" \
		""
	opencode_case "an unrelated blocker doesn't block the open session" \
		"$started permission.asked:other-child:p9 $succeeded" "working done"
	opencode_case "an unknown session's events write nothing" \
		"session.execution.started:ghost permission.asked:ghost:p1" ""
	opencode_case "nothing counts while no session is open" \
		"route:home $started permission.asked:root:p1" ""
	opencode_case "with a subagent session open, its root's events count" \
		"route:child $started permission.asked:grandchild:p1" "working blocked"
	opencode_case "switching sessions: the new one drives the Status from its next event" \
		"$started permission.asked:root:p1 route:other $succeeded session.execution.failed:other" \
		"working blocked failed"
	opencode_case "switching sessions drops the old session's blockers" \
		"$started permission.asked:root:p1 route:other session.execution.started:other" \
		"working blocked working"

	begin "opencode: cleanup unsets both once and stops listening"
	run_opencode "$opencode_plugin" "$started" cleanup "$succeeded" permission.asked:root:p1
	expect_tmux "$opencode_agent" "$(opencode_status working)" "$opencode_unset"

	begin "opencode: TMUX_PANE unset writes nothing"
	(
		unset TMUX_PANE
		run_opencode "$opencode_plugin" "$started" permission.asked:root:p1 cleanup
	) || exit 1
	expect_tmux

	begin "opencode: empty TMUX_PANE writes nothing"
	TMUX_PANE= run_opencode "$opencode_plugin" "$started" "$succeeded"
	TMUX_PANE=%99
	expect_tmux

	begin "opencode: a failing tmux is ignored"
	FAKE_TMUX_FAIL=1 run_opencode "$opencode_plugin" "$started" "$failed" cleanup
	unset FAKE_TMUX_FAIL
	expect_tmux "$opencode_agent" "$(opencode_status working)" "$(opencode_status failed)" "$opencode_unset"
}

opencode_install_cases() {
	begin "opencode install: first run says installed"
	new_home
	mkdir -p "$HOME/.config/opencode"
	printf '%s\n' '{ "plugin": ["./other.js"] }' >"$HOME/.config/opencode/tui.jsonc"
	printf '%s\n' '{ "model": "openai/gpt-5" }' >"$HOME/.config/opencode/opencode.json"
	cp -R "$HOME/.config/opencode" "$work/opencode-original"
	run_install
	expect_install_line opencode "opencode: installed"
	[ "$install_rc" -eq 0 ] || fail "installer exited $install_rc:" "$install_out"
	pass

	begin "opencode install: copies the plugin directory, not a symlink"
	plugin_dir=$HOME/.config/opencode/plugins/muxify-status
	[ -d "$plugin_dir" ] && [ ! -L "$plugin_dir" ] || fail "missing or a symlink: $plugin_dir"
	[ ! -L "$plugin_dir/tui.js" ] || fail "a symlink: $plugin_dir/tui.js"
	diff -r "$ext/opencode/muxify-status" "$plugin_dir" >/dev/null ||
		fail "differs from the source:" "$(diff -r "$ext/opencode/muxify-status" "$plugin_dir")"
	pass

	begin "opencode install: no config file is touched"
	[ "$(cd "$HOME/.config/opencode" && find . -type f | sort)" = "$(printf '%s\n' ./opencode.json ./plugins/muxify-status/tui.js ./tui.jsonc)" ] ||
		fail "unexpected files:" "$(cd "$HOME/.config/opencode" && find . -type f)"
	expect_same_file "$work/opencode-original/tui.jsonc" "$HOME/.config/opencode/tui.jsonc"
	expect_same_file "$work/opencode-original/opencode.json" "$HOME/.config/opencode/opencode.json"
	pass

	begin "opencode install: the installed plugin reports"
	run_opencode "$plugin_dir/tui.js" session.execution.started:root
	expect_tmux "$opencode_agent" "$(opencode_status working)" "$opencode_unset"

	begin "opencode install: second run says updated and replaces the plugin"
	echo '// stale' >"$plugin_dir/tui.js"
	echo '// dropped' >"$plugin_dir/old.js"
	run_install
	expect_install_line opencode "opencode: updated"
	diff -r "$ext/opencode/muxify-status" "$plugin_dir" >/dev/null ||
		fail "differs from the source:" "$(diff -r "$ext/opencode/muxify-status" "$plugin_dir")"
	expect_same_file "$work/opencode-original/tui.jsonc" "$HOME/.config/opencode/tui.jsonc"
	pass

	begin "opencode install: no .config/opencode prints not found and creates nothing"
	new_home
	mkdir "$HOME/.config"
	run_install
	expect_install_line opencode "opencode: not found"
	[ "$(find "$HOME" -mindepth 1)" = "$HOME/.config" ] || fail "created:" "$(find "$HOME" -mindepth 1)"
	pass
}

# --- Pi ---------------------------------------------------------------------

pi_extension=$ext/pi/muxify-status.ts
pi_driver=$work/pi-driver.mjs
pi_agent='set -p -t %99 @muxify_agent pi'
pi_unset='set -p -u -t %99 @muxify_agent ; set -p -u -t %99 @muxify_agent_status'

# A fake Pi: loads the extension (Node strips its types), calls the default
# export with a fake pi that records the handlers registered with pi.on, and
# fires the steps given as arguments, in order, with a fake ctx (TUI mode,
# idle unless told otherwise):
#   <event>[:<arg>]   fires that Pi event; agent_end:<r1>,<r2>… carries a user
#                     message and one assistant message per stopReason;
#                     session_shutdown:<reason> carries that reason
#   mode:<mode>       ctx.mode from now on (tui, rpc, json, print)
#   busy | idle       what ctx.isIdle() answers from now on
# The process then exits normally.
cat >"$pi_driver" <<'JS'
import { pathToFileURL } from "node:url";

const [file, ...steps] = process.argv.slice(2);
const { default: extension } = await import(pathToFileURL(file).href);
if (typeof extension !== "function") {
	console.error("default export is not a function (pi)");
	process.exit(2);
}

// Every event Pi 0.85 lets an extension subscribe to.
const events = new Set([
	"project_trust", "resources_discover", "session_start", "session_info_changed",
	"session_before_switch", "session_before_fork", "session_before_compact",
	"session_compact", "session_compact_failed", "session_shutdown",
	"session_before_tree", "session_tree", "context", "before_provider_request",
	"before_provider_headers", "after_provider_response", "before_agent_start",
	"agent_start", "agent_end", "agent_settled", "ui_prompt_start", "ui_prompt_end",
	"turn_start", "turn_end", "message_start", "message_update", "message_end",
	"tool_execution_start", "tool_execution_update", "tool_execution_end",
	"model_select", "thinking_level_select", "tool_call", "tool_result", "user_bash",
	"input",
]);
const handlers = new Map();
const pi = {
	on(event, handler) {
		if (!events.has(event) || typeof handler !== "function") {
			console.error(`pi.on(${JSON.stringify(event)}, ${typeof handler}) is not a Pi event handler`);
			process.exit(2);
		}
		handlers.set(event, [...(handlers.get(event) ?? []), handler]);
	},
};

let mode = "tui";
let idle = true;
const ctx = {
	get mode() {
		return mode;
	},
	get hasUI() {
		return mode === "tui" || mode === "rpc";
	},
	cwd: process.cwd(),
	isIdle: () => idle,
};

function payload(type, arg) {
	switch (type) {
		case "session_start":
			return { type, reason: "startup" };
		case "agent_end": {
			const messages = [{ role: "user", content: "hi", timestamp: 0 }];
			for (const stopReason of arg ? arg.split(",") : []) {
				if (messages.length > 1) {
					messages.push({ role: "toolResult", toolCallId: "t", toolName: "bash", content: [], isError: false, timestamp: 0 });
				}
				messages.push({ role: "assistant", content: [], stopReason, timestamp: 0 });
			}
			return { type, messages };
		}
		case "ui_prompt_start":
		case "ui_prompt_end":
			return { type, reason: "ui_prompt", kind: "confirm", title: "Proceed?" };
		case "session_shutdown":
			return { type, reason: arg };
		default:
			return { type };
	}
}

await extension(pi);
for (const step of steps) {
	const [type, arg] = step.split(":");
	if (type === "mode") mode = arg;
	else if (type === "busy") idle = false;
	else if (type === "idle") idle = true;
	else for (const handler of handlers.get(type) ?? []) await handler(payload(type, arg), ctx);
}
JS

# pi_write <what>: the tmux call for <what>: "agent" names the Agent only,
# "unset" unsets both options, "none" unsets the Status and keeps the Agent,
# anything else publishes that Status.
pi_write() {
	case $1 in
	agent) printf '%s\n' "$pi_agent" ;;
	unset) printf '%s\n' "$pi_unset" ;;
	none) printf '%s\n' "$pi_agent ; set -p -u -t %99 @muxify_agent_status" ;;
	*) printf '%s\n' "$pi_agent ; set -p -t %99 @muxify_agent_status $1" ;;
	esac
}

# run_pi <extension> [step...]: the fake Pi must exit 0 and print nothing.
run_pi() {
	pi_out=$(node --disable-warning=ExperimentalWarning "$pi_driver" "$@" 2>&1)
	pi_rc=$?
	[ "$pi_rc" -eq 0 ] || fail "exited $pi_rc:" "$pi_out"
	[ -z "$pi_out" ] || fail "printed: $pi_out"
}

# pi_case <name> <steps> <writes>: runs the space-separated steps and expects
# exactly the space-separated writes (see pi_write), in order.
pi_case() {
	begin "pi: $1"
	# shellcheck disable=SC2086 # steps are split on purpose
	run_pi "$pi_extension" $2
	pi_writes=$3
	set --
	for write in $pi_writes; do
		set -- "$@" "$(pi_write "$write")"
	done
	expect_tmux "$@"
}

pi_hook_cases() {
	start="session_start agent_start"

	pi_case "session_start names the Agent only" "session_start" "agent"
	pi_case "agent_start -> working" "$start" "agent working"
	pi_case "a dialog -> blocked, closing it -> working" \
		"$start ui_prompt_start ui_prompt_end" "agent working blocked working"
	pi_case "agent_end with error + settled -> failed" \
		"$start agent_end:error agent_settled" "agent working failed"
	pi_case "agent_end aborted (Esc) + settled -> done" \
		"$start agent_end:aborted agent_settled" "agent working done"
	pi_case "agent_end with stop + settled -> done" \
		"$start agent_end:stop agent_settled" "agent working done"
	pi_case "the last assistant message's stopReason counts" \
		"$start agent_end:toolUse,error agent_settled" "agent working failed"
	pi_case "a run without an assistant message settles done" \
		"$start agent_end agent_settled" "agent working done"
	pi_case "a retried run is judged by its last agent_end" \
		"$start agent_end:error agent_start agent_end:stop agent_settled" "agent working done"
	pi_case "settled while not idle writes nothing" \
		"$start agent_end:error busy agent_settled" "agent working"
	pi_case "a repeated agent_start is written once" "$start agent_start" "agent working"
	pi_case "a new run after failed -> working" \
		"$start agent_end:error agent_settled agent_start" "agent working failed working"
	pi_case "a dialog before any run -> blocked, then no Status" \
		"session_start ui_prompt_start ui_prompt_end" "agent blocked none"
	pi_case "a run settling under a dialog shows once it closes" \
		"$start ui_prompt_start agent_end:error agent_settled ui_prompt_end" "agent working blocked failed"
	pi_case "quit unsets both" "$start session_shutdown:quit" "agent working unset"
	pi_case "events after quit write nothing" \
		"$start session_shutdown:quit agent_start ui_prompt_start session_shutdown:quit" "agent working unset"
	for reason in reload new resume fork; do
		pi_case "session_shutdown for $reason writes nothing" \
			"$start session_shutdown:$reason" "agent working"
	done
	for mode in json print rpc; do
		pi_case "$mode mode writes nothing" \
			"mode:$mode $start ui_prompt_start ui_prompt_end agent_end:error agent_settled session_shutdown:quit" ""
	done

	begin "pi: TMUX_PANE unset writes nothing"
	(
		unset TMUX_PANE
		run_pi "$pi_extension" $start ui_prompt_start session_shutdown:quit
	) || exit 1
	expect_tmux

	begin "pi: empty TMUX_PANE writes nothing"
	TMUX_PANE= run_pi "$pi_extension" $start agent_end:stop agent_settled
	TMUX_PANE=%99
	expect_tmux

	begin "pi: a failing tmux is ignored"
	FAKE_TMUX_FAIL=1 run_pi "$pi_extension" $start agent_end:error agent_settled session_shutdown:quit
	unset FAKE_TMUX_FAIL
	expect_tmux "$(pi_write agent)" "$(pi_write working)" "$(pi_write failed)" "$(pi_write unset)"
}

pi_install_cases() {
	begin "pi install: first run says installed"
	new_home
	mkdir -p "$HOME/.pi/agent"
	printf '%s\n' '{ "defaultModel": "opus" }' >"$HOME/.pi/agent/settings.json"
	cp "$HOME/.pi/agent/settings.json" "$work/pi-settings.json"
	run_install
	expect_install_line pi "pi: installed"
	[ "$install_rc" -eq 0 ] || fail "installer exited $install_rc:" "$install_out"
	pass

	begin "pi install: creates extensions/ and copies the file, not a symlink"
	pi_installed=$HOME/.pi/agent/extensions/muxify-status.ts
	[ -f "$pi_installed" ] && [ ! -L "$pi_installed" ] || fail "missing or a symlink: $pi_installed"
	expect_same_file "$pi_extension" "$pi_installed"
	pass

	begin "pi install: nothing else is touched"
	[ "$(cd "$HOME/.pi/agent" && find . -type f | sort)" = "$(printf '%s\n' ./extensions/muxify-status.ts ./settings.json)" ] ||
		fail "unexpected files:" "$(cd "$HOME/.pi/agent" && find . -type f)"
	expect_same_file "$work/pi-settings.json" "$HOME/.pi/agent/settings.json"
	pass

	begin "pi install: the installed extension reports"
	run_pi "$pi_installed" session_start agent_start
	expect_tmux "$(pi_write agent)" "$(pi_write working)"

	begin "pi install: second run says updated, replaces the file, keeps other extensions"
	echo '// stale' >"$pi_installed"
	echo '// other' >"$HOME/.pi/agent/extensions/other.ts"
	run_install
	expect_install_line pi "pi: updated"
	expect_same_file "$pi_extension" "$pi_installed"
	[ "$(cat "$HOME/.pi/agent/extensions/other.ts")" = '// other' ] || fail "other.ts changed"
	pass

	begin "pi install: a symlink in its place becomes a copy, its target untouched"
	echo '// target' >"$work/pi-target.ts"
	rm "$pi_installed"
	ln -s "$work/pi-target.ts" "$pi_installed"
	run_install
	expect_install_line pi "pi: updated"
	[ -f "$pi_installed" ] && [ ! -L "$pi_installed" ] || fail "still a symlink: $pi_installed"
	expect_same_file "$pi_extension" "$pi_installed"
	[ "$(cat "$work/pi-target.ts")" = '// target' ] || fail "the symlink's target changed"
	pass

	begin "pi install: no .pi/agent prints not found and creates nothing"
	new_home
	mkdir "$HOME/.pi"
	run_install
	expect_install_line pi "pi: not found"
	[ "$(find "$HOME" -mindepth 1)" = "$HOME/.pi" ] || fail "created:" "$(find "$HOME" -mindepth 1)"
	pass
}

# --- Run --------------------------------------------------------------------

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found" >&2; exit 1; }

claude_hook_cases
claude_install_cases
codex_hook_cases
codex_install_cases
opencode_hook_cases
opencode_install_cases
pi_hook_cases
pi_install_cases

echo "ok: $passed checks passed"
