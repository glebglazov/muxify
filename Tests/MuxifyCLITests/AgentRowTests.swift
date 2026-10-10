import XCTest
@testable import MuxifyCLI
import MuxifyCore

final class AgentRowTests: XCTestCase {
    private func window(_ id: String, session: (id: String, name: String), topic: String) -> String {
        (["W", id, session.id, session.name, "1", "zsh", "", "/work", "zsh", "1", "2", "0", "0"]
            + ["", "", "", "", "", "", topic, "/work", "", ""]).joined(separator: Tmux.separator)
    }

    private func pane(_ id: String, window: String, command: String, agent: String, status: String, unread: Bool) -> String {
        ["P", id, window, command, agent, status, unread ? "1" : "", "", "1", "0", "/work", ""].joined(separator: Tmux.separator)
    }

    func testEachPaneThatRunsAnAgentIsARowWithTheOpenTopicOfItsSession() {
        let snapshot = Tmux.parseSnapshot([
            window("@1", session: ("$1", "game/ship"), topic: "ship"),
            window("@2", session: ("$2", "loose"), topic: ""),
            window("@3", session: ("$3", "game/old"), topic: "old"),
            pane("%1", window: "@1", command: "zsh", agent: "", status: "", unread: false),
            pane("%2", window: "@1", command: "2.1.289", agent: "claude", status: "blocked", unread: true),
            pane("%3", window: "@2", command: "codex", agent: "codex", status: "", unread: false),
            pane("%4", window: "@2", command: "zsh", agent: "claude", status: "done", unread: true),
            pane("%5", window: "@3", command: "node", agent: "opencode", status: "working", unread: false),
        ].joined(separator: "\n"))
        var settled = TopicRecord(id: "old", title: "Old")
        settled.settledAt = "2026-10-01T10:00:00Z"
        let rows = AgentRow.list(snapshot: snapshot, records: [TopicRecord(id: "ship", title: "Ship"), settled])
        XCTAssertEqual(rows, [
            AgentRow(paneID: "%2", windowID: "@1", sessionID: "$1", sessionName: "game/ship",
                     agent: .init(kind: .claude, status: .blocked, unread: true), topic: TopicSummary(id: "ship", label: "Ship")),
            AgentRow(paneID: "%3", windowID: "@2", sessionID: "$2", sessionName: "loose",
                     agent: .init(kind: .codex, status: nil, unread: false), topic: nil),
            AgentRow(paneID: "%5", windowID: "@3", sessionID: "$3", sessionName: "game/old",
                     agent: .init(kind: .opencode, status: .working, unread: false), topic: nil),
        ], "a Pane back at a shell is no Agent, and a Settled Topic is no Topic")
    }
}
