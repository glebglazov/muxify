#!/bin/sh
# Tests the Extensions and the installer without any Agent installed.
#
#   sh extensions/test.sh
#
# A fake tmux (prepended to PATH) appends each invocation's arguments as one
# line to a log, and TMUX_PANE is a fake Pane id, so each case feeds an
# Extension an Agent event and asserts the tmux calls it made. Installer cases
# run against a temporary HOME; the real HOME is never touched. Stops at the
# first mismatch, naming the case, and exits non-zero. Needs jq, and node for
# the OpenCode plugin, which a small Node script drives with a fake api.
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

# --- Run --------------------------------------------------------------------

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found" >&2; exit 1; }

claude_hook_cases
claude_install_cases
opencode_hook_cases
opencode_install_cases

echo "ok: $passed checks passed"
