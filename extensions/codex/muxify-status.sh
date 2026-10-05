#!/bin/sh
# Muxify Extension for Codex CLI.
#
# Reports this Agent and its Status on its own tmux Pane through the pane
# options @muxify_agent and @muxify_agent_status (docs/adr/0004). Codex runs
# this one script for every hook event it is registered for in
# ~/.codex/hooks.json (through the user's login shell) and passes the event as
# JSON on stdin. The script never prints anything (stdout of some hooks becomes
# model context) and always exits 0, whatever tmux, ps or jq do.
#
# Known gaps: no hook fires when a turn fails, so there is no failed Status;
# blocked lasts until an approved command finishes (its PostToolUse); the
# Agent appears only at its first prompt, when Codex fires SessionStart.

# Leaves without writing anything. Reads the rest of the event first, so Codex
# never hits a closed pipe while it is still writing a large payload.
quit() {
	[ -t 0 ] || cat >/dev/null 2>&1
	exit 0
}

# Outside tmux there is no Pane to report on.
[ -n "${TMUX_PANE:-}" ] || quit

# Daemon guard. By default Codex runs conversations in a shared background
# daemon (codex app-server --managed-daemon), whose TMUX_PANE belongs to
# whichever Pane happened to start it, so a hook run by the daemon would report
# on the wrong Pane. Walk a handful of ancestors (the login shell running this
# script, then Codex, ...) and stay silent if one of them is the daemon.
pid=$PPID
depth=0
while [ "$depth" -lt 8 ]; do
	case $pid in '' | 0 | 1 | *[!0-9]*) break ;; esac
	# "<ppid> <args>", possibly with leading blanks; -ww never truncates args.
	info=$(ps -ww -o ppid= -o args= -p "$pid" 2>/dev/null) || break
	case $info in *--managed-daemon*) quit ;; esac
	info=${info#"${info%%[! ]*}"}
	pid=${info%%[! 0-9]*}
	pid=${pid%% *}
	depth=$((depth + 1))
done

# Read the event once. Payloads carrying an agent_id come from subagents and
# yield an empty event, so only the main conversation drives the Status.
# request_user_input (Codex asking the user a question) gets its own event.
event=$(jq -r '
	if (.agent_id // "") != "" then ""
	elif .hook_event_name == "PreToolUse" and .tool_name == "request_user_input" then "PreToolUse:request_user_input"
	else .hook_event_name // ""
	end' 2>/dev/null) || exit 0

pane=$TMUX_PANE

case $event in
SessionStart)
	# Name the Agent, but leave the Status alone: no turn has run yet.
	tmux set -p -t "$pane" @muxify_agent codex >/dev/null 2>&1
	exit 0
	;;
SessionEnd)
	tmux set -p -u -t "$pane" @muxify_agent \; set -p -u -t "$pane" @muxify_agent_status >/dev/null 2>&1
	exit 0
	;;
UserPromptSubmit | PreToolUse | PostToolUse)
	status=working
	;;
PreToolUse:request_user_input | PermissionRequest)
	status=blocked
	;;
Stop | Interrupt)
	# Interrupt is Esc: the turn is over, so it counts as done.
	status=done
	;;
*)
	exit 0
	;;
esac

# Name the Agent with every Status, so an Extension installed in the middle of
# a conversation (after its SessionStart) still shows up.
tmux set -p -t "$pane" @muxify_agent codex \; set -p -t "$pane" @muxify_agent_status "$status" >/dev/null 2>&1
exit 0
