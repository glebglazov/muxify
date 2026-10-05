#!/bin/sh
# Muxify Extension for Claude Code.
#
# Reports this Agent and its Status on its own tmux Pane through the pane
# options @muxify_agent and @muxify_agent_status (docs/adr/0004). Claude Code
# runs this one script for every hook event it is registered for and passes the
# event as JSON on stdin. The script never prints anything (stdout of some hooks
# becomes model context) and always exits 0 (a failing Stop hook would keep the
# turn going), whatever tmux or jq do.
#
# Known gap: Claude Code fires no hook when a turn is interrupted with Esc or a
# permission prompt is denied, so the Status keeps its last value until the
# next event.

# Outside tmux there is no Pane to report on.
[ -n "${TMUX_PANE:-}" ] || exit 0

# Read the event once. Payloads carrying an agent_id come from subagents and
# yield an empty event, so only the main conversation drives the Status.
event=$(jq -r 'if (.agent_id // "") != "" then "" else (.hook_event_name // "") end' 2>/dev/null) || exit 0

pane=$TMUX_PANE

case $event in
SessionStart)
	# Name the Agent, but leave the Status alone: no turn has run yet.
	tmux set -p -t "$pane" @muxify_agent claude >/dev/null 2>&1
	exit 0
	;;
SessionEnd)
	tmux set -p -u -t "$pane" @muxify_agent \; set -p -u -t "$pane" @muxify_agent_status >/dev/null 2>&1
	exit 0
	;;
UserPromptSubmit | PostToolUse | ElicitationResult)
	status=working
	;;
PermissionRequest | Elicitation | PreToolUse)
	# PreToolUse is registered only for AskUserQuestion|ExitPlanMode.
	status=blocked
	;;
Stop)
	status=done
	;;
StopFailure)
	status=failed
	;;
*)
	exit 0
	;;
esac

# Name the Agent with every Status, so an Extension installed in the middle of
# a conversation (after its SessionStart) still shows up.
tmux set -p -t "$pane" @muxify_agent claude \; set -p -t "$pane" @muxify_agent_status "$status" >/dev/null 2>&1
exit 0
