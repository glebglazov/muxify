# Muxify

A native macOS (SwiftUI + AppKit) front end for tmux. It renders the terminal with
**libghostty**, shows tmux windows in a sidebar, and has a WebKit browser that
opens as a panel on the right.

```
┌──────────────┬───────────────────────────────┬────────────────────────────┐
│ session      │                               │ ‹ › ⟳ [Search or enter URL] │
│ ▌~/w/project │   tmux window, all splits,    │                            │
│   master     │   rendered by libghostty      │        WKWebView           │
│   ~/work/... │                               │   (one page per tmux       │
│  ~/p/other   │                               │    window)                 │
│   main       │                               │                            │
└──────────────┴───────────────────────────────┴────────────────────────────┘
```

## Build & run

```sh
make run          # vendors libghostty, generates the Xcode project, builds, opens the app
```

Requirements: Xcode, `xcodegen` (`brew install xcodegen`), and `tmux`. Ghostty.app
must be installed: its terminfo and themes are copied into the app bundle at build
time.

The libghostty static library comes from a `GhosttyKit.xcframework`. By default
`scripts/setup-ghostty.sh` picks up the local build in
`~/projects/ghostty-remux-upstream-rebuild`. To use a different one:

```sh
GHOSTTYKIT=/path/to/GhosttyKit.xcframework ./scripts/setup-ghostty.sh
# or build from a ghostty checkout (needs zig):
GHOSTTY_SRC=~/src/ghostty ./scripts/setup-ghostty.sh
```

You can also open `Muxify.xcodeproj` in Xcode after `make project`.

## How it works

The vocabulary (Session, Window, Pane, Browser, Tab) is defined in
[CONTEXT.md](CONTEXT.md); the decisions behind the design are in
[docs/adr](docs/adr).

- **Terminal.** One libghostty surface runs a single `tmux attach` client,
  attached straight to your Sessions. tmux draws the Window with all its Panes.
  Your normal Ghostty config (`~/.config/ghostty/config`) is loaded, so fonts,
  theme and keybinds match standalone Ghostty, including the `cmd+…` → tmux
  prefix bindings. `Ghostty/TerminalSurfaceView.swift` forwards keyboard/IME,
  mouse, scroll, size, scale and focus to libghostty, following Ghostty's own
  macOS `SurfaceView`.
- **Sidebar.** The sidebar reads `tmux list-windows -a` + `list-clients` once a
  second and lists every Session in tmux order. Sessions are collapsible
  groups; the current one opens automatically, and which ones are open is
  remembered. Each Window row shows:
  - a title: the pane title (fish sets it to `~/w/project`), falling back to the
    window name
  - the git branch, read from `.git/HEAD`
  - a globe with the Tab count, if the Window's Browser has Tabs
  - the pane count
  - bell/activity dots

  Hovering a row shows its path. Clicking a row runs `switch-client -c <our tty>
  -t <window>`. Because Muxify attaches directly, other terminals on the same
  Session switch with it. Navigating inside tmux (prefix+n, choose-tree, …) moves
  the sidebar selection too. On launch Muxify returns to the Window you last
  had selected (`@muxify_last_window`, a server-wide tmux option).
- **Browser.** Each Window has its own Browser in a panel on the right: a tab
  strip, back/forward/reload, an omnibox (URLs, bare hosts like `localhost:3000`,
  or search terms) and the page (WKWebView). Whether it's open, its Tabs and the
  active Tab are stored on the tmux Window itself (`@muxify_tabs`,
  `@muxify_active_tab`, `@muxify_browser`), so they come back after relaunching
  Muxify and disappear with the Window.
  - Cmd+click on a link in the terminal, or a link that would open a new window,
    opens a new Tab. If that URL is already open, Muxify switches to that Tab.
  - Closing the last Tab closes the Browser.
  - Restored Tabs load the first time you look at them. All Tabs share one
    login profile.
  - A blank Tab lists TCP ports that the Window's processes are listening on
    (`lsof` over the pane process tree), so you can open a dev server in one
    click.

## Shortcuts

Browser shortcuts work when focus is in the Browser. In the terminal, your
Ghostty/tmux bindings keep their meaning.

| Shortcut | In the Browser |
| --- | --- |
| ⌘T / ⌘W | New Tab / close Tab |
| ⌘⇧] / ⌘⇧[, ⌃Tab / ⌃⇧Tab | Next / previous Tab |
| ⌘L | Focus the address bar |
| ⌘[ / ⌘] / ⌘R | Back / forward / reload |

| Shortcut | Anywhere |
| --- | --- |
| ⇧⌘B | Show/hide this Window's Browser |
| ⌘1–9 | Select tmux Window 1–9 of the current Session |
| ⌘\` | Focus terminal |
| ⌘N | New tmux Session |
| ⌃⌘S | Toggle sidebar |

⌘W never closes the app window. Ghostty actions are mapped to tmux:
- `new_tab` → new window
- `new_split` → `split-window`
- `goto_split` → `select-pane`
- `toggle_split_zoom` → `resize-pane -Z`

## Scripting

Programs running inside a Window can open Tabs in that Window's Browser. If you
are looking at another Window, the Tab opens quietly and you aren't moved.

```sh
tmux set -w @muxify_open localhost:3000          # from inside the Window
tmux set -w @muxify_open "localhost:3000 localhost:6006"   # several at once
open "muxify://open?url=localhost:3000&window=$(tmux display -p '#{window_id}')"
open "muxify://select?window=@12"
open "muxify://toggle-browser"
```

## Proof-of-concept limits

- The sidebar polls tmux every second, so `@muxify_open` can take up to a second.
  Using tmux control mode (`-C`) would make updates push-based.
- The Browser is WebKit, not Chromium (ADR 0002): no Chrome extensions, and no
  CDP for agents.
- There is no terminal search UI, and no inspector or quick-look.
- The sidebar shows Windows only, not individual Panes.
