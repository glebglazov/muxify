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

The vocabulary (Session, Window, Pane, Browser, Tab, Agent, Status, Extension)
is defined in
[CONTEXT.md](CONTEXT.md); the decisions behind the design are in
[docs/adr](docs/adr).

- **Terminal.** One libghostty surface runs a single `tmux attach` client,
  attached straight to your Sessions. tmux draws the Window with all its Panes.
  Your normal Ghostty config (`~/.config/ghostty/config`) is loaded, so fonts,
  theme and keybinds match standalone Ghostty, including the `cmd+…` → tmux
  prefix bindings. `Ghostty/TerminalSurfaceView.swift` forwards keyboard/IME,
  mouse, scroll, size, scale and focus to libghostty, following Ghostty's own
  macOS `SurfaceView`.
- **Sidebar.** The sidebar lists every Session in tmux order, from `tmux
  list-windows -a` + `list-clients`. A read-only tmux control-mode client
  (`tmux -C`) reports Window switches, new and closed Windows and renames as they
  happen. Titles, paths and bells are polled once a second. Sessions are collapsible
  groups; the current one opens automatically, and which ones are open is
  remembered. Each Window row shows:
  - the logo of what its active Pane runs: the Agent reporting there, else the
    command (`Resources/Logos/<command>.svg` or `.png`, e.g. `nvim`, `node`; a
    version suffix and case are ignored, and a few commands share a logo, such
    as `cargo` → `rust`; shells get `terminal`), else the terminal logo. On a dark theme
    `<command>.dark.svg` is used when there is one
  - a title: the pane title (fish sets it to `~/w/project`), falling back to the
    window name; the glyph Claude Code puts in front is dropped
  - a globe with the Tab count, if the Window's Browser has Tabs
  - the pane count
  - a dot if a Pane rang the bell

  Hovering a row shows its path. Clicking a row runs `switch-client -c <our tty>
  -t <window>`. Because Muxify attaches directly, other terminals on the same
  Session switch with it. Navigating inside tmux (prefix+n, choose-tree, …) moves
  the sidebar selection too. On launch Muxify returns to the Window you last
  had selected (`@muxify_last_window`, a server-wide tmux option).

  Below Sessions, the **Agents** section lists the coding Agents (Claude Code,
  Codex, OpenCode, Pi) running in your Panes, in tmux order. Each Agent's
  Extension writes two tmux pane options on its own Pane: `@muxify_agent`
  (`claude`, `codex`, `opencode` or `pi`) and `@muxify_agent_status`
  (`working`, `blocked`, `done` or `failed`; unset until the first turn).
  Muxify reads them with `list-panes -a` in the same once-a-second poll. A row
  shows the Agent's icon, its Window's title (without the glyph Claude Code
  puts in front) and `session:window`, and a dot: blue working, orange blocked,
  red failed, green done but unread. An Agent becomes **unread** when it
  reaches done, failed or blocked while you aren't looking at its Window (the
  Window is selected and Muxify is in front); looking at it makes it read.
  Muxify keeps this on the Pane as `@muxify_agent_unread`, so it survives a
  relaunch. A read Agent that is done, or hasn't run a turn yet, has no dot.
  Unread Agents are listed first, then working ones, then the rest, each in
  tmux order. A Pane that is back at a plain shell is hidden, in case a
  crashed Agent left its options behind. Clicking a row switches to the Window and
  selects the Agent's Pane. The Extensions live in [extensions/](extensions);
  the contract is
  [ADR 0004](docs/adr/0004-agents-report-status-through-pane-options.md).
  View → Show Sessions and Show Agents hide either section; the other then
  fills the sidebar, and with both hidden the sidebar stays open but empty. With both shown, drag the
  divider between them to resize; the split is remembered.
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
| ⌘B | Show/hide this Window's Browser |
| ⌘\` | Focus terminal |
| ⌘N | New tmux Session |
| ⌘S (or ⌃⌘S) | Toggle sidebar |

⌘W never closes the app window. Ghostty actions are mapped to tmux:
- `new_tab` → new window
- `new_split` → `split-window`
- `goto_split` → `select-pane`
- `toggle_split_zoom` → `resize-pane -Z`

## Scripting

Programs running inside a Window can open Tabs in that Window's Browser. If you
are looking at another Window, the Tab opens quietly and you aren't moved.

Install the `muxify` command with **Muxify ▸ Install Command Line Tool** (it
links into `~/.local/bin`), then run it in any Pane:

```sh
muxify browser open localhost:3000                 # this Pane's Window
muxify browser open localhost:3000 localhost:6006  # several Tabs
muxify browser open --window @12 localhost:3000    # another Window
```

It finds its Window from `$TMUX_PANE`, so it also works from callers that have
no tty (an agent's shell tool, a background job). Outside tmux it asks for
`--window`.

Without the tool, set the option yourself. Always pass `-t "$TMUX_PANE"`:
without it, a caller that has no tty gets the session's current Window, not its
own.

```sh
tmux set -w -t "$TMUX_PANE" @muxify_open localhost:3000          # from inside the Window
tmux set -w -t "$TMUX_PANE" @muxify_open "localhost:3000 localhost:6006"   # several at once
open "muxify://open?url=localhost:3000&window=$(tmux display -p -t "$TMUX_PANE" '#{window_id}')"
open "muxify://select?window=@12"
open "muxify://toggle-browser"
```

## Proof-of-concept limits

- Pane titles, paths, bells, Agent Statuses and `@muxify_open` are polled once
  a second, so they can take up to a second to show up.
- The Browser is WebKit, not Chromium (ADR 0002): no Chrome extensions, and no
  CDP for agents.
- There is no terminal search UI, and no inspector or quick-look.
- The Sessions list shows Windows only, not individual Panes; only Panes
  running an Agent appear, in the Agents section.
