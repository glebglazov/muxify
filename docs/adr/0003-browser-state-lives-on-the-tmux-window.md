# Browser state lives on the tmux Window

Each Window's Browser state is stored on the Window itself as tmux window options, not in Muxify's preferences. That state is its Tabs, the active Tab, and whether the Browser is open. Programs inside a Window open a Tab by setting the one-shot option `@muxify_open`, which Muxify consumes and clears. They must target their own pane (`tmux set -w -t "$TMUX_PANE" @muxify_open <url>`): without `-t`, tmux resolves a caller that has no tty to the session's current Window.

tmux reuses window ids after a server restart, so preferences keyed by id would attach old Tabs to unrelated Windows. On the Window, the state lives and dies with it. The cost: Browser state doesn't survive a tmux server restart. That's acceptable because the Windows don't survive it either (no tmux-resurrect).
