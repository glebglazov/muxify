# Extensions

An Extension is the small piece installed into a coding Agent's own hook or
plugin system that tells Muxify which Agent runs in a Pane and what it is
doing. There is one folder per Agent:

| Folder    | Agent       | Extension                         |
| --------- | ----------- | --------------------------------- |
| `claude/` | Claude Code | `muxify-status.sh`, a hook script |

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
it if it is already there) and prints one line per Agent: `claude: installed`,
`claude: updated` or `claude: not found` (or `claude: failed (<reason>)`).
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

## Tests

```sh
sh extensions/test.sh
```

The script needs only `jq`; no Agent has to be installed. It puts a fake `tmux`
first on `PATH` that logs each invocation's arguments, sets `TMUX_PANE` to a
fake Pane id (`%99`), feeds each Extension sample events and checks the logged
tmux calls. It then runs `install.sh` against temporary home directories (with
foreign hooks to preserve, without `settings.json`, without the Agent's config
directory, without `jq`) and checks the copied files, the added hook entries,
the `.bak` copy and that a second run leaves `settings.json` byte-identical. The
real home directory is never touched. It stops at the first mismatch, printing
the failing case, and exits non-zero; on success it prints
`ok: <n> checks passed`.
