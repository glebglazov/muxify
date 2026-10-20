# Agent rules for Muxify

## End-to-end checks

To prove a change in the running app, use the e2e harness in `scripts/verify/`. Do not write your own. Read `scripts/verify/README.md` before you run, add or change a check.

- `make verify` builds the Debug app and runs every suite in `scripts/verify/suites/`. `make verify SUITE=<suite>` runs one suite.
- Add a check that must stay true to its feature's suite, and commit it with the feature. Keep one-off probes in the run directory.
- Checks must not take focus from the user. Follow "Do not take focus" in `scripts/verify/README.md`: reach a context-menu behavior through an accessibility action, not through the menu.

## Actions and Commands

Design every new Action or Command as steps in the palette's view: run at once, choose a row, pick, type one value, or confirm. Read `docs/adr/0014-every-action-runs-in-the-palettes-view.md` before you add or change one. For an Action on several Topics, use the pick step in `Sources/Muxify/UI/PalettePick.swift`, with its chips in `Sources/Muxify/UI/PaletteChips.swift`, and read `docs/adr/0025-a-pick-step-collects-topics-and-tags-as-chips.md`. A sheet or an alert that takes input needs its own ADR first.

## tmux in tests and verification

The default tmux server (socket `${TMUX_TMPDIR:-/tmp}/tmux-<uid>/default`) and any server the user started with `-L` or `-S` are the user's live work. Every test, script and Muxify copy you start talks to a **throwaway server** only. `Sandbox` does this for you. If you must start tmux some other way:

- Give each run its own directory. Set `TMUX_TMPDIR` to it, and remove `TMUX` and `TMUX_PANE` from the environment of every process you start. tmux uses the socket in `$TMUX` before `TMUX_TMPDIR`, so a leftover `TMUX` sends the command to the user's server.
- Before you run `kill-server`, `kill-session`, `kill-window`, Settle or any other destructive step, run `tmux display -p '#{socket_path}'` with the same environment. Continue only when the path is inside your run directory.
- When you finish, stop your own processes by PID and run `kill-server` on your throwaway server only.

Never kill, Settle or change Sessions on the user's default server, and never stop or restart the user's `/Applications/Muxify.app`. If a check needs the real server, stop and ask the user.
