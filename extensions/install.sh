#!/bin/sh
# Installs or updates the Muxify Extension of every Agent set up under $HOME.
#
# Muxify ▸ Install Extensions runs the copy of this script bundled inside the
# app; the Extension files are found next to it, so the bundled installer
# installs the bundled Extensions. An Agent counts as set up when its config
# directory exists (a Finder-launched app can't rely on PATH to find the
# Agents' binaries). Running it again updates the Extensions and adds nothing
# twice.
#
# Prints exactly one line per Agent:
#   <agent>: installed | updated | not found | failed (<reason>)
# and exits non-zero when any Agent failed.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
failed=0

# add_hook_entries <file> <entries>
#
# <entries> is a JSON object {"<Event>": <entry>, ...}, each entry in the
# hooks-file shape {"matcher"?: "...", "hooks": [{"type": "command",
# "command": "...", ...}]}. Appends each entry to the file's .hooks.<Event>
# list unless that event already has a hook running the identical command.
# Other entries, their order and every other key are left as they are. When
# something is added, the file is first copied to <file>.bak; when nothing is
# missing, neither file is written. A missing or empty file counts as {}.
add_hook_entries() {
	hooks_file=$1
	merged=$(
		{ if [ -s "$hooks_file" ]; then cat "$hooks_file"; else echo '{}'; fi; } |
			jq --argjson add "$2" '
				. as $doc
				| def runs($cmd): any((.hooks // [])[]; .command == $cmd);
				reduce ($add | to_entries[]) as $e (.;
					if any((.hooks[$e.key] // [])[]; runs($e.value.hooks[0].command)) then .
					else .hooks[$e.key] = (.hooks[$e.key] // []) + [$e.value]
					end)
				| if . == $doc then empty else . end'
	) || return 1
	[ -n "$merged" ] || return 0
	if [ -e "$hooks_file" ]; then
		cp -p "$hooks_file" "$hooks_file.bak" || return 1
	fi
	printf '%s\n' "$merged" >"$hooks_file"
}

# Claude Code: one hook script for every event, registered in settings.json.
install_claude() {
	claude_dir=$HOME/.claude
	if [ ! -d "$claude_dir" ]; then
		echo "claude: not found"
		return 0
	fi
	if ! command -v jq >/dev/null 2>&1; then
		echo "claude: failed (jq not found)"
		return 1
	fi

	claude_script=$claude_dir/hooks/muxify-status.sh
	# $HOME stays literal: Claude Code expands it when it runs the hook.
	claude_command='sh "$HOME/.claude/hooks/muxify-status.sh"'
	# Synchronous (no "async") so events stay in order.
	claude_entries=$(jq -n --arg cmd "$claude_command" '
		reduce ("SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
			"PostToolUse", "Elicitation", "ElicitationResult", "Stop", "StopFailure",
			"SessionEnd") as $event ({};
			.[$event] =
				(if $event == "PreToolUse" then {matcher: "AskUserQuestion|ExitPlanMode"} else {} end)
				+ {hooks: [{type: "command", command: $cmd, timeout: 5}]})')

	if [ -e "$claude_script" ]; then result=updated; else result=installed; fi
	if ! { mkdir -p "$claude_dir/hooks" &&
		cp "$here/claude/muxify-status.sh" "$claude_script" &&
		chmod 755 "$claude_script"; }; then
		echo "claude: failed (could not copy the hook script)"
		return 1
	fi
	if ! add_hook_entries "$claude_dir/settings.json" "$claude_entries"; then
		echo "claude: failed (could not update settings.json)"
		return 1
	fi
	echo "claude: $result"
}

for agent in claude; do
	"install_$agent" || failed=1
done
exit "$failed"
