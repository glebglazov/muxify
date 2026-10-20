# End-to-end checks run a real Muxify against a private tmux server in a sandbox

We prove app behavior with end-to-end checks that drive a Debug build of Muxify against a real tmux server. Each run gets its own sandbox: its own directory, tmux server, Config, state and copy of the app. The harness in `scripts/verify/` has a generic layer, written once (`sandbox.py` and the Debug-only `TestDriver.swift`), and one small suite per feature on top. We chose a real tmux server because tmux is the source of truth (ADR 0001), so a fake tmux would test our assumptions, not tmux. We chose a sandbox that the code enforces because agents that wrote their own harnesses killed the user's tmux Sessions.

## Considered Options

- **Each agent writes its own harness for each task.** This is how it started. Rejected: each copy wrote the isolation code again, and one leftover `TMUX` variable is enough to send a `kill-server` to the user's server. Checks were lost with their `/tmp` directory, so a real bug they found was never followed up.
- **A UI driver injected into the app as a dylib (`DYLD_INSERT_LIBRARIES`).** Rejected: it is not compiled with the app, so it drifts from the app without a warning. The driver is now a Debug-only part of the app.
- **A sandbox that agents must keep by following rules in `AGENTS.md`.** Rejected as the only guard: the rules are still there, but the guards are in code. `Sandbox.tmux` always names the sandbox socket with `-S`. The TestDriver exits if `TMUX` is set or `TMUX_TMPDIR` is outside the sandbox. Teardown stops only processes it started, by PID, or processes that name the sandbox in their command line or environment.
- **Parallel runs as a feature now.** Deferred: nobody needs them yet. Each run has its own root (`<suite>/<run-id>/`) and bundle id, so two runs do not share a tmux server or app copy. A run only removes the roots of runs whose owner process is gone. Nothing else coordinates them, and nothing is tested in parallel.

## Consequences

- A check that must stay true is committed with its feature, in that feature's suite. A one-off probe stays in the run directory. `scripts/verify/README.md` has the rules for writing checks.
- Two runs can happen at the same time, for example when the user and an agent run checks together. We accept that risk without a guard. The known effect is timing checks that get noisier.
- Checks run while the user works, so they must not take focus. `Sandbox.launch` starts the app through LaunchServices with `open -g`, so the app starts behind the user's front app. The driver has no command that activates the app or opens a context menu. A check reaches a context-menu behavior through an accessibility action on the view.
- The app's tmux control client starts on a pty that is its controlling terminal. When Muxify dies, the kernel hangs up that terminal and the client exits. On pipes, tmux 3.7c can leave the client running, and the client then keeps a killed server alive.
