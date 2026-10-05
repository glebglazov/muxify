# Extensions

An Extension is the small piece installed into a coding Agent's own hook or
plugin system that tells Muxify which Agent runs in a Pane and what it is
doing. There is one folder per Agent:

| Folder      | Agent       | Extension                                   |
| ----------- | ----------- | ------------------------------------------- |
| `claude/`   | Claude Code | `muxify-status.sh`, a hook script           |
| `opencode/` | OpenCode 2  | `muxify-status/`, a TUI plugin directory    |
| `pi/`       | Pi          | `muxify-status.ts`, an extension file       |

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
`claude: installed`, `opencode: updated` or `pi: not found` (or
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

For Pi (detected by `~/.pi/agent`), the installer copies `pi/muxify-status.ts`
to `~/.pi/agent/extensions/muxify-status.ts` (creating `extensions/` if needed;
a copy, not a symlink, and a symlink already there is replaced). Pi loads every
`.ts` file in that folder by itself, so no config file is edited. Restart
running Pi sessions (or run `/reload` in them) to load it.

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

## Pi

`pi/muxify-status.ts` is a Pi extension (Pi 0.85, `@earendil-works/pi-coding-agent`):
a single TypeScript file whose default export is `function (pi)`, registering
its handlers with `pi.on`. It reports only when `ctx.mode` is `"tui"`: Pi
processes started in `json`, `print` or `rpc` mode (subagents, scripts) inherit
the Pane's `TMUX_PANE` and stay silent. It writes synchronously, so the writes
follow event order. It uses only TypeScript that Node can run by stripping
types (no enums, namespaces or parameter properties), so the tests load it with
plain Node 24.

| Pi event                                   | Status                                    |
| ------------------------------------------ | ----------------------------------------- |
| `session_start`                            | sets `@muxify_agent` only                 |
| `agent_start`                              | working                                   |
| `ui_prompt_start` (a dialog opens)         | blocked                                   |
| `ui_prompt_end` (the dialog closes)        | back to the run's Status (unset if no run yet) |
| `agent_end`                                | remembers the last assistant message's `stopReason` |
| `agent_settled`, when `ctx.isIdle()`       | failed if that `stopReason` is `error`, otherwise done (Esc, `aborted`, counts as done) |
| `session_shutdown` with reason `quit`      | unsets both options                       |
| anything else                              | nothing                                   |

`agent_start` can fire more than once for one prompt (retries, compaction,
queued messages); the run ends only at `agent_settled`, which Pi fires once when
nothing more will run. A `session_shutdown` for `reload`, `new`, `resume` or
`fork` writes nothing, since Pi keeps running and the reloaded extension names
the Agent again. A Status is written only when it changes.

Blocked only appears while a dialog is open: `ui_prompt_start` and
`ui_prompt_end` (Pi ≥ 0.84.4) wrap every `select`, `confirm`, `input`, `editor`
or custom dialog that any extension opens. Pi has no permission prompts of its
own, so a run without such a dialog goes straight from working to done or
failed.

Known gap: a `/new`, `/resume` or `/fork` session keeps the previous session's
last Status until its first run starts.

## Tests

```sh
sh extensions/test.sh
```

The script needs only `jq` and `node` (24 or later); no Agent has to be installed. It puts a
fake `tmux` first on `PATH` that logs each invocation's arguments, sets
`TMUX_PANE` to a fake Pane id (`%99`), feeds each Extension sample events and
checks the logged tmux calls. Shell hooks get the event JSON on stdin; the
OpenCode plugin is loaded by a small Node script that calls `setup` with a fake
`api` (a session tree with a subagent, an unrelated session, a router showing
the root session) and emits events through the captured `listen` callback. The
Pi extension is loaded the same way (Node 24 strips its types), its default
export is called with a fake `pi` that records the `pi.on` handlers, and the
events are fired with a fake `ctx` whose `mode` and `isIdle()` each case sets.
It then runs `install.sh` against temporary home directories (with foreign hooks
to preserve, without `settings.json`, without the Agent's config directory,
without `jq`) and checks the copied files, the added hook entries, the `.bak`
copy and that a second run leaves `settings.json` byte-identical. The
real home directory is never touched. It stops at the first mismatch, printing
the failing case, and exits non-zero; on success it prints
`ok: <n> checks passed`.
