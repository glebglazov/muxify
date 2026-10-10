# Sidebar Formats are expanded by Muxify, with a subset of tmux's syntax

The user can set the title and the Summary of Topic cards, Session cards, Window rows, Pane rows and Agent rows with a Format in the Config. Muxify expands every Format with its own evaluator, which reads a subset of tmux's format syntax: `#{name}`, `#{?cond,a,b}`, `#{==:a,b}`, `#{=N:name}`, `#{b:name}` and the `#{S:…}`, `#{W:…}`, `#{P:…}` loops. A variable that names a tmux thing keeps tmux's name (`window_name`, `pane_current_command`). A Muxify thing uses its glossary name (`topic_title`, `project`, `branch`, `agent_status`). Topic cards are not tmux objects, so Muxify needs its own evaluator for them in any case. One evaluator gives one language with the same variables everywhere, in a Remote Environment too. Because Muxify knows every name, a typo is a Config problem with a line number, not a silent empty string.

Title and Summary Formats give plain text. Window `left` and `right` Formats can also produce the current app icon or a named macOS SF Symbol. The shared parser returns typed text and image elements for these parts. Variable values remain text and cannot introduce an image expression. Scalar operations accept text only. Config validates symbol availability before a row renders. This keeps invalid symbols and image operands in Config diagnostics, instead of silently dropping them in the UI.

An omitted or null part keeps its native content. An empty output hides the part. Each part can differ by Sidebar mode. Custom right content replaces the Tab and Pane badges. It does not replace the bell.

Agent Formats use the Agent's own Pane context, including its Window, Session and Topic values. The default title is `#{pane_label}`. The default Summary is `#{agent_group}`, which preserves the existing group text and scope rules. A custom Summary appears when its expansion is not empty, even in a scoped section. The Agent hover label uses the formatted title. Its Status detail does not change.

Sidebar typography keeps control of font, size and color. `#[` is reserved, so styled runs such as `#[fg=red]` can come later without breaking a Config.

## Considered Options

- **Send names Muxify does not know to tmux.** Rejected: any tmux variable or `@option` would work in rows, but Muxify could not tell a typo from a tmux name, and the list of names it polls would grow with each Config.
- **Let tmux expand Window and Pane rows, and Muxify only the cards.** Rejected: two languages with different variables, and rows would have no Agent or branch variables.
