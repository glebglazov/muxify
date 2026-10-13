import XCTest
@testable import MuxifyCore

final class AgentUnreadTests: XCTestCase {
    private func pane(_ status: String, unread: Bool = false, command: String = "sleep") -> TmuxPane {
        TmuxPane(id: "%1", windowID: "@1", command: command, agent: "claude", agentStatus: status, unread: unread)
    }

    func testManualReadRecordsUpdatesEvenInTheWindowBeingViewed() {
        for status in ["done", "failed", "blocked"] {
            XCTAssertEqual(AgentUnread.change(for: pane(status), previousStatus: "working", visited: true, manualRead: true), true)
            XCTAssertNil(AgentUnread.change(for: pane(status, unread: true), previousStatus: status, visited: true, manualRead: true))
            XCTAssertNil(AgentUnread.change(for: pane(status), previousStatus: status, visited: true, manualRead: true),
                         "Mark Read stays read until another observed Status change")
            XCTAssertNil(AgentUnread.change(for: pane("working"), previousStatus: status, visited: true, manualRead: true))
            XCTAssertEqual(AgentUnread.change(for: pane(status), previousStatus: "working", visited: true, manualRead: true), true)
        }
    }

    func testAutomaticReadingClearsVisitedAgentsAndSkipsTheirUpdates() {
        for status in ["done", "failed", "blocked"] {
            XCTAssertNil(AgentUnread.change(for: pane(status), previousStatus: "working", visited: true, manualRead: false))
            XCTAssertEqual(AgentUnread.change(for: pane(status), previousStatus: "working", visited: false, manualRead: false), true)
            XCTAssertEqual(AgentUnread.change(for: pane(status, unread: true), previousStatus: status, visited: true, manualRead: false), false)
        }
    }

    func testInitialSnapshotAndExitedAgents() {
        for manualRead in [true, false] {
            XCTAssertNil(AgentUnread.change(for: pane("done"), previousStatus: nil, visited: false, manualRead: manualRead))
            XCTAssertEqual(AgentUnread.change(for: pane("done", unread: true, command: "zsh"), previousStatus: "done",
                                              visited: false, manualRead: manualRead), false)
        }
    }
}
