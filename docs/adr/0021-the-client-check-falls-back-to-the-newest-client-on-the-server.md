# The Client check falls back to the newest Client on the server

[0015](0015-programs-find-muxify-by-the-client-you-typed-into.md) looks only at the Clients of the Pane's own Session. Muxify has one Client for each App Window and moves it between Sessions with `switch-client`. So while you look at another Session in Muxify, the Pane's Session has no Client, and an Agent that checks at that moment gets `no` and opens its page outside Muxify. `muxify browser open` does not need you on that Window: Muxify reads `@muxify_open` on every Window and opens the Tab without moving you. We keep the Session's own Clients first. When no non-control Client shows the Pane's Session, the check takes the newest non-control Client on the whole server, with `tmux list-clients` without `-t`, and matches it against the `@muxify_client_*` options as before. The script in `docs/configuration.md` and `muxify browser available` ([0017](0017-muxify-browser-available-runs-the-client-check.md)) both do this, and the e2e check runs both on a Pane whose Session no Client shows.

## Considered Options

- **Only the newest Client on the server.** Rejected: a Session open in Ghostty.app gets `local` when you last typed in Muxify, and its page goes to a Browser you do not look at. The Session's own Clients answer that case better.
- **A marker on each Session that Muxify showed.** Rejected: it adds a part to the protocol, and nothing clears it when you later attach Ghostty.app to that Session and detach again, so it gives a false `local`.

## Consequences

A Session that only Ghostty.app ever showed, with Ghostty.app now detached, gets `local` when you last typed in Muxify. Nobody shows that Session, so the Tab waits in that Window's Browser in Muxify, where you work. The answer is still for the moment of the check.
