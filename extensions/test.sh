#!/bin/sh
# Tests the Extensions and the installer without any Agent installed.
#
#   sh extensions/test.sh
#
# A fake tmux (prepended to PATH) appends each invocation's arguments as one
# line to a log, and TMUX_PANE is a fake Pane id, so each case feeds an
# Extension an Agent event and asserts the tmux calls it made. Installer cases
# run against a temporary HOME; the real HOME is never touched. Stops at the
# first mismatch, naming the case, and exits non-zero. Needs jq.
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

# --- Run --------------------------------------------------------------------

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found" >&2; exit 1; }

claude_hook_cases
claude_install_cases

echo "ok: $passed checks passed"
