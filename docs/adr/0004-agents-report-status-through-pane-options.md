# Agents report their Status through tmux pane options

Each Agent's Extension sets two options on its own Pane: `@muxify_agent` names the Agent (`claude`, `codex`, `opencode` or `pi`) and `@muxify_agent_status` holds its Status (`working`, `blocked`, `done` or `failed`). Extensions write them with `tmux set -p -t "$TMUX_PANE" …` and unset both when the Agent exits. Muxify reads them in the snapshot it already polls once a second. The Agent has to name itself because the process name can't identify it: Claude Code's pane command is its version number, such as `2.1.289`.

This keeps tmux the single source of truth (ADR 0001). An Extension needs nothing but the `tmux` binary, so a one-file hook script works as well as an in-process plugin, and the Status outlives a Muxify restart.

## Considered Options

- **A socket served by Muxify, like herdr's.** Rejected: the Extension would then need a client protocol and a way to find the socket, and it would lose reports sent while Muxify isn't running.
- **Reusing `@agent-status`.** Rejected: the Raycast tmux-ai-agents extension's hooks already write it with other values (`idle`, `unread`), and Raycast ignores values it doesn't know.

## Consequences

An Agent killed without a chance to clean up (crash, `kill -9`) leaves its options behind. To cover that, Muxify hides an Agent whose Pane is back at a plain shell.

Whether an Agent is Unread is kept the same way, in a third pane option, `@muxify_agent_unread`. Muxify sets and clears it itself, because only Muxify knows whether you are looking at the Window; the Extensions don't touch it.
