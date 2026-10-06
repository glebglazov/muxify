# Muxify

A native macOS app for running coding agents in tmux. It lists your tmux
Sessions and Windows in a sidebar, shows which Agents (Claude Code, Codex,
OpenCode, Pi) are working, blocked or done and waiting for you, and gives every
Window its own browser panel for docs and dev servers.

## How it works

Muxify runs a single `tmux attach` client in a libghostty terminal, so tmux
draws your Windows and Panes exactly as it does in Ghostty, with your
`~/.config/ghostty/config`. A tmux control-mode client and a once-a-second poll
keep the sidebar in sync, and Muxify keeps its own state (Browser Tabs, Agent
Statuses) in tmux options on the Window or Pane it belongs to, so it survives a
relaunch and goes away with the Window. Agents report their Status through small
Extensions installed into each Agent's own hook or plugin system. The vocabulary
is in [CONTEXT.md](CONTEXT.md), the design decisions in [docs/adr](docs/adr).

## Build

Requires macOS 14+ on Apple silicon, Xcode, `xcodegen` (`brew install
xcodegen`), `tmux`, Ghostty.app (its terminfo and themes are bundled into the
app) and a `GhosttyKit.xcframework`.

```sh
make run    # vendors libghostty, generates the Xcode project, builds and opens the app
```

`scripts/setup-ghostty.sh` looks for a local Ghostty build in `~/projects/`. To
use another one:

```sh
GHOSTTYKIT=/path/to/GhosttyKit.xcframework ./scripts/setup-ghostty.sh
GHOSTTY_SRC=~/src/ghostty ./scripts/setup-ghostty.sh    # builds it with zig
```

## Install

```sh
cp -R build/Build/Products/Debug/Muxify.app /Applications/
```

Then open that copy and, from the **Muxify** menu:

- **Install Command Line Tool** links `muxify` into `~/.local/bin`. Programs in
  a Pane use it to open Tabs in their Window's Browser (`muxify browser open
  localhost:3000`), and launchers use it to jump to a Session (`muxify session
  open "my project"`). The link points into the app bundle, so install it from
  the copy you keep.
- **Install Extensions** installs or updates the status Extension for every
  supported Agent it finds in your home directory: Claude Code, Codex, OpenCode
  and Pi. Claude Code and Codex need `jq`. For Codex, trust the hooks once with
  `/hooks` and launch it with `codex --no-daemon`. Restart running Agents to
  load the Extension. See [extensions/README.md](extensions/README.md) for what
  each one does.
