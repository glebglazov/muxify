# tmux is the source of truth for Sessions, Windows and Panes

Muxify is a tmux client, not a terminal multiplexer of its own. It has no model of Panes or splits. The terminal is one `tmux attach` client rendered by libghostty, and tmux draws every Window with its splits. Without a tmux server, Muxify starts one.

We chose this over native splits (as in Ghostty or cmux) because the workflow this serves is already tmux-native. tmux gives persistence, detach and existing keybindings for free, and a second pane model would double the state to keep in sync.
