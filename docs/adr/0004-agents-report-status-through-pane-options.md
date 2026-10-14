# Agents report their Status through tmux pane options

The Claude Code, OpenCode and Pi Extensions set three options on its own Pane: `@muxify_agent` names the Agent (`claude`, `codex`, `opencode` or `pi`), `@muxify_agent_status` holds its Status (`working`, `blocked`, `done` or `failed`), and `@muxify_agent_conversation` holds the Agent's conversation id. Extensions write them with `tmux set -p -t "$TMUX_PANE" …` and unset all three when the Agent exits. Muxify reads them in the snapshot it already polls once a second. The Agent has to name itself because the process name can't identify it: Claude Code's pane command is its version number, such as `2.1.289`.

This keeps tmux the single source of truth (ADR 0001). An Extension needs nothing but the `tmux` binary, so a one-file hook script works as well as an in-process plugin, and the Status outlives a Muxify restart.

## Considered Options

- **A socket served by Muxify, like herdr's.** Rejected: the Extension would then need a client protocol and a way to find the socket, and it would lose reports sent while Muxify isn't running.
- **Reusing `@agent-status`.** Rejected: the Raycast tmux-ai-agents extension's hooks already write it with other values (`idle`, `unread`), and Raycast ignores values it doesn't know.

## Consequences

An Agent killed without a chance to clean up (crash, `kill -9`) leaves its options behind. To cover that, Muxify hides an Agent whose Pane is back at a plain shell.

Whether an Agent is Unread is kept the same way, in a fourth pane option, `@muxify_agent_unread`. Muxify sets and clears it itself, because only Muxify knows whether you are looking at the Window; the Extensions don't touch it.

## Codex daemon reporting

Codex's default daemon runs hooks with the daemon's environment. Its
`TMUX_PANE` can belong to a different conversation or tmux server. The Extension
therefore writes a report by conversation ID to the account's fixed
`$HOME/.local/state/muxify/codex` directory. It does not choose a Pane or server.

The installer enables Codex's native `thread-id` terminal-title item. Each TUI
sets the title of its own Pane. Muxify's shared snapshot reader joins that title
to the report and exposes the same Agent fields to the app, CLI and Topics.
Only a foreground `codex` command uses this join. Ambiguous prefixes provide no
Status or full conversation ID. Other Agents still use pane-option reports. Old Codex pane options cannot
override the join and are ignored when the foreground command changes.

This is an exception to storing all Agent Status in tmux. It avoids a server
registry, a new background process and a requirement to disable Codex's daemon.
The snapshot stays read-only. Reports are read through the selected server's
`run-shell`, including over SSH. The final remote inventory includes reports
before its connection closes. No report contains a socket path or Pane ID.

`SessionEnd` clears Status and retains the conversation ID. It does not prove
that every TUI for the conversation has closed. The current Pane command
controls Agent lifetime. Normal polls read only current conversation prefixes,
so old reports do not increase the set of files read on each poll.
