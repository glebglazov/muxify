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

- **Terminal.** One libghostty surface runs a single `tmux attach` client. tmux
  draws the window and all its splits. Your normal Ghostty config
  (`~/.config/ghostty/config`) is loaded, so fonts, theme and keybinds match
  standalone Ghostty, including the `cmd+…` → tmux prefix bindings.
  `Ghostty/TerminalSurfaceView.swift` forwards keyboard/IME, mouse, scroll, size,
  scale and focus to libghostty, following Ghostty's own macOS `SurfaceView`.
- **Sidebar.** The sidebar reads `tmux list-windows -a` + `list-clients` once a
  second. Sessions are collapsible groups; the current one opens automatically,
  and which ones are open is remembered. Each window row shows:
  - a title: the pane title (fish sets it to `~/w/project`), falling back to the
    window name
  - the git branch, read from `.git/HEAD`
  - the pane count
  - bell/activity dots

  Hovering a row shows its path.

  Clicking a row runs `switch-client -c <our tty> -t <window>`. Navigating inside
  tmux (prefix+n, choose-tree, …) moves the sidebar selection too.
- **No interference with other terminals.** Clients attached to the same tmux
  session share its current window. So Muxify attaches to a grouped *view
  session* (`<name>·muxify`, created with `new-session -t <session>`). It has the
  same windows but its own current window, so switching windows in Muxify never
  moves the other terminals attached to that session. View sessions are tagged
  `@muxify_view`, hidden from the sidebar, and use `destroy-unattached`, so tmux
  deletes them when Muxify leaves them or quits.
- **Browser.** A WKWebView in a SwiftUI `.inspector` panel. Each tmux window has
  its own page, kept alive when you switch windows and restored on relaunch.
  The address bar takes URLs, bare hosts (`localhost:3000` gets `http://`) or
  search terms. If a tmux window has no page yet, the panel lists TCP ports that
  the window's processes are listening on (`lsof` over the pane process tree), so
  you can open a dev server in one click. Cmd+click on a link in the terminal
  opens it in the panel.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘B | Show/hide browser |
| ⌘L | Focus the address bar (only when your Ghostty config doesn't bind ⌘L to something else) |
| ⌘[ / ⌘] / ⌘R | Browser back / forward / reload (while the browser is open) |
| ⌘\` | Focus terminal |
| ⌘T / ⌘N | New tmux window / session (unless your Ghostty config rebinds them) |
| ⌃⌘S | Toggle sidebar |

Ghostty actions are mapped to tmux:
- `new_tab` → new window
- `new_split` → `split-window`
- `goto_split` → `select-pane`
- `toggle_split_zoom` → `resize-pane -Z`

## Scripting

```sh
open "muxify://open?url=localhost:3000&window=$(tmux display -p '#{window_id}')"
open "muxify://select?window=@12"
open "muxify://toggle-browser"
```

## Proof-of-concept limits

- The sidebar polls tmux every second. Using tmux control mode (`-C`) would make
  updates push-based.
- The browser is WebKit. A Chromium engine, as in ChatGPT Atlas, would be a much
  bigger project.
- There are no browser tabs or history UI within a window.
- There is no terminal search UI, and no inspector or quick-look.
- The sidebar shows windows only, not individual panes.
