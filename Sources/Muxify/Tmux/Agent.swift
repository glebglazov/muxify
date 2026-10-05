import Foundation

/// Which coding-agent CLI an Agent is, as its Extension names it in the Pane's
/// `@muxify_agent` option (ADR 0004). The raw value is also its icon's name.
enum AgentKind: String, CaseIterable {
    case claude, codex, opencode, pi

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .pi: return "Pi"
        }
    }
}

/// What an Agent is doing, from the Pane's `@muxify_agent_status` option.
enum AgentStatus: String {
    case working, blocked, done, failed
}

/// An Agent running in a Pane, as listed in the sidebar's Agents section.
struct Agent: Identifiable, Hashable {
    /// The Pane the Agent runs in, e.g. "%42".
    let paneID: String
    let kind: AgentKind
    /// nil until the Agent has run a turn.
    let status: AgentStatus?
    let windowID: String
    let sessionID: String
    let sessionName: String
    let windowIndex: Int
    /// The Window's `displayTitle`.
    let windowTitle: String

    var id: String { paneID }

    /// `session:window`, e.g. `muxify:2`.
    var location: String { "\(sessionName):\(windowIndex)" }

    /// One Agent per Pane whose `@muxify_agent` names a known Agent, in tmux
    /// order (Session, Window, Pane). A Pane back at a plain shell is skipped:
    /// an Agent killed without cleaning up leaves its options behind.
    static func list(panes: [TmuxPane], windows: [TmuxWindow]) -> [Agent] {
        let windowsByID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return panes.compactMap { pane in
            guard let kind = AgentKind(rawValue: pane.agent),
                  !Tmux.shellNames.contains(pane.command),
                  let window = windowsByID[pane.windowID]
            else { return nil }
            return Agent(
                paneID: pane.id,
                kind: kind,
                status: AgentStatus(rawValue: pane.agentStatus),
                windowID: window.id,
                sessionID: window.sessionID,
                sessionName: window.sessionName,
                windowIndex: window.index,
                windowTitle: window.displayTitle
            )
        }
    }
}
