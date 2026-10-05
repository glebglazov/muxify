# Extensions

An Extension is the small piece installed into a coding Agent's own hook or
plugin system that tells Muxify which Agent runs in a Pane and what it is
doing. There is one folder per Agent:

| Folder      | Agent       | Extension                                   |
| ----------- | ----------- | ------------------------------------------- |
| `claude/`   | Claude Code | `muxify-status.sh`, a hook script           |
| `opencode/` | OpenCode 2  | `muxify-status/`, a TUI plugin directory    |

## What an Extension does

Each Extension writes two tmux pane options on the Agent's own Pane
([ADR 0004](../docs/adr/0004-agents-report-status-through-pane-options.md)):

| Option                | Values                                  |
| --------------------- | --------------------------------------- |
| `@muxify_agent`       | `claude`, `codex`, `opencode` or `pi`   |
| `@muxify_agent_status`| `working`, `blocked`, `done` or `failed`; unset = no Status yet |

- Every write targets the Agent's own Pane: `tmux set -p -t "$TMUX_PANE" …`.
- A Status write sets both options in one tmux call
  (`tmux set -p -t P @muxify_agent claude \; set -p -t P @muxify_agent_status working`),
  so an Extension installed in the middle of a conversation still names its
  Agent.
- When the Agent exits normally, both options are unset (`set -p -u`).
- Outside tmux (`TMUX_PANE` empty) an Extension does nothing, and it never
  fails the Agent's hook: tmux errors are ignored.

Muxify reads both options in its once-a-second tmux poll and lists the Agent in
the sidebar's Agents section with a Status dot: working blue, blocked orange,
done green, failed red, no dot without a Status. An Agent whose Pane is back at
a plain shell is hidden, which covers options left behind by a crash.

## Install

Choose **Muxify ▸ Install Extensions**. It runs `install.sh` from the copy of
this folder bundled inside the app, which, for every Agent whose config
directory exists under your home directory, installs the Extension (or updates
it if it is already there) and prints one line per Agent, such as
`claude: installed`, `opencode: updated` or `opencode: not found` (or
`claude: failed (<reason>)`).
Running it again changes nothing but the Extension files themselves, so it is
also how you update.

For Claude Code (detected by `~/.claude`), the installer:

- copies `claude/muxify-status.sh` to `~/.claude/hooks/muxify-status.sh`
  (a copy, not a symlink);
- adds one hook entry per event below to `~/.claude/settings.json`, each
  running `sh "$HOME/.claude/hooks/muxify-status.sh"` synchronously (so events
  stay in order) with a 5 second timeout. The `PreToolUse` entry has the
  matcher `AskUserQuestion|ExitPlanMode`;
- copies `settings.json` to `settings.json.bak` before changing it, adds an
  entry only when that event has no hook with the identical command yet, never
  touches or reorders other entries (Raycast, herdr, lavish …) or other keys,
  and leaves both files alone when nothing is missing;
- needs `jq`; without it, it prints `claude: failed (jq not found)` and changes
  nothing.

For OpenCode 2 (detected by `~/.config/opencode`), the installer replaces
`~/.config/opencode/plugins/muxify-status/` with a copy of
`opencode/muxify-status/`. OpenCode discovers the plugin there by itself, so no
config file is edited. Restart running OpenCode TUIs to load it.

To try the installer without touching your real setup, point it at a scratch
home: `HOME=$(mktemp -d) sh extensions/install.sh`.

## Claude Code

`claude/muxify-status.sh` is a POSIX `sh` script that handles every hook event.
Claude Code passes the event as JSON on stdin; the script reads
`hook_event_name` with `jq`, ignores payloads carrying an `agent_id` (they come
from subagents, so only the main conversation drives the Status), prints
nothing and always exits 0.

| Hook event                                        | Status                          |
| ------------------------------------------------- | ------------------------------- |
| `SessionStart`                                    | sets `@muxify_agent` only       |
| `UserPromptSubmit`, `PostToolUse`, `ElicitationResult` | working                    |
| `PermissionRequest`, `Elicitation`                | blocked                         |
| `PreToolUse` (`AskUserQuestion`, `ExitPlanMode`)  | blocked                         |
| `Stop`                                            | done                            |
| `StopFailure`                                     | failed                          |
| `SessionEnd`                                      | unsets both options             |
| anything else                                     | nothing                         |

Known gap: Claude Code fires no hook when you press Esc to interrupt a turn or
deny a permission prompt, so the Status keeps its last value (working or
blocked) until the next event, such as your next prompt.

## OpenCode 2

`opencode/muxify-status/tui.js` is an OpenCode 2 TUI plugin (an ES module
exporting `{ id: "muxify.agent-status", setup(api) }`). Each OpenCode TUI loads
its own copy, so it reports on the Pane that TUI runs in. It listens to every
event with `api.data.listen` and writes synchronously, so the writes follow
event order.

All TUIs share one OpenCode server and see the events of every session on it,
so the plugin counts only events from the session open in its own TUI
(`api.ui.router.current()`) and that session's subagents: an event counts when
walking `parentID` up from its session reaches the same root session as the
open one. Events from other sessions, or while no session is open, write
nothing.

| Event                                                   | Status                          |
| ------------------------------------------------------- | ------------------------------- |
| plugin setup (TUI start)                                | sets `@muxify_agent` only       |
| `session.execution.started` (root session)              | working                         |
| `session.execution.succeeded` (root session)            | done                            |
| `session.execution.interrupted` (root session, e.g. Esc) | done                            |
| `session.execution.failed` (root session)               | failed                          |
| `permission.asked`, `form.created` (any session in the tree) | blocked until answered     |
| `permission.replied`, `form.replied`, `form.cancelled`  | back to the last execution Status |
| cleanup (plugin unloaded) or process exit               | unsets both options             |

While any permission or form in the tree is pending the Status is blocked;
once none is, it is the root session's last execution Status (unset if no
execution has been seen yet). Subagent sessions' own executions are ignored. A
Status is written only when it changes.

Known gap: the plugin reads which session is open only when an event arrives,
so after you switch to another session inside one TUI the Status still shows
the previous session's until the new session's next event (for example its
next execution starting). Requests that were pending in the previous session
are forgotten on the switch.

## Tests

```sh
sh extensions/test.sh
```

The script needs only `jq` and `node`; no Agent has to be installed. It puts a
fake `tmux` first on `PATH` that logs each invocation's arguments, sets
`TMUX_PANE` to a fake Pane id (`%99`), feeds each Extension sample events and
checks the logged tmux calls. Shell hooks get the event JSON on stdin; the
OpenCode plugin is loaded by a small Node script that calls `setup` with a fake
`api` (a session tree with a subagent, an unrelated session, a router showing
the root session) and emits events through the captured `listen` callback. It
then runs `install.sh` against temporary home directories (with foreign hooks
to preserve, without `settings.json`, without the Agent's config directory,
without `jq`) and checks the copied files, the added hook entries, the `.bak`
copy and that a second run leaves `settings.json` byte-identical. The
real home directory is never touched. It stops at the first mismatch, printing
the failing case, and exits non-zero; on success it prints
`ok: <n> checks passed`.
