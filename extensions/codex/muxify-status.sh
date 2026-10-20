#!/bin/sh
# Codex's daemon has no reliable Pane environment. Muxify joins these reports
# to the conversation identifier emitted by each TUI in its terminal title.

umask 077
record=$(jq -sce '
	select(length == 1) | .[0]
	| select(type == "object" and (.agent_id // "") == "")
	| select(.session_id | type == "string")
	| select(.session_id | length == 36)
	| select(.session_id | test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"))
	| .hook_event_name as $event
	| (if $event == "SessionStart" or $event == "SessionEnd" then null
		elif $event == "PreToolUse" and .tool_name == "request_user_input" then "blocked"
		elif $event == "PermissionRequest" then "blocked"
		elif $event == "UserPromptSubmit" or $event == "PreToolUse" or $event == "PostToolUse" then "working"
		elif $event == "Stop" or $event == "Interrupt" then "done"
		else empty end) as $status
	| {version: 1, conversation: (.session_id | ascii_downcase), status: $status}
' 2>/dev/null) || exit 0
conversation=$(printf '%s' "$record" | jq -r '.conversation' 2>/dev/null) || exit 0
# The daemon and Muxify can have different XDG_STATE_HOME values. Both use
# the account home so they always reach the same conversation reports.
reports=$HOME/.local/state/muxify/codex
report=$reports/$conversation.json

mkdir -p "$reports" 2>/dev/null || exit 0
temporary=$(mktemp "$reports/.report.XXXXXXXX" 2>/dev/null) || exit 0
trap 'rm -f "$temporary" 2>/dev/null' EXIT HUP INT TERM
if printf '%s\n' "$record" >"$temporary" 2>/dev/null; then
	mv -f "$temporary" "$report" 2>/dev/null
fi
exit 0
