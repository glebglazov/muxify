import XCTest
@testable import MuxifyCore

final class AgentUnreadTests: XCTestCase {
    private func pane(_ status: String, unread: Bool = false, command: String = "sleep") -> TmuxPane {
        TmuxPane(id: "%1", windowID: "@1", command: command, agent: "claude", agentStatus: status, unread: unread)
    }

    func testManualReadRecordsUpdatesEvenInTheWindowBeingViewed() {
        for status in ["done", "failed", "blocked"] {
            XCTAssertEqual(AgentUnread.change(for: pane(status), previousStatus: "working", reading: .visiting, manualRead: true), true)
            XCTAssertNil(AgentUnread.change(for: pane(status, unread: true), previousStatus: status, reading: .visiting, manualRead: true))
            XCTAssertNil(AgentUnread.change(for: pane(status), previousStatus: status, reading: .visiting, manualRead: true),
                         "Mark Read stays read until another observed Status change")
            XCTAssertNil(AgentUnread.change(for: pane("working"), previousStatus: status, reading: .visiting, manualRead: true))
            XCTAssertEqual(AgentUnread.change(for: pane(status), previousStatus: "working", reading: .visiting, manualRead: true), true)
        }
    }

    func testAutomaticReadingClearsVisitedAgentsAndSkipsTheirUpdates() {
        for status in ["done", "failed", "blocked"] {
            XCTAssertNil(AgentUnread.change(for: pane(status), previousStatus: "working", reading: .visiting, manualRead: false))
            XCTAssertEqual(AgentUnread.change(for: pane(status), previousStatus: "working", reading: .away, manualRead: false), true)
            XCTAssertEqual(AgentUnread.change(for: pane(status, unread: true), previousStatus: status, reading: .visiting, manualRead: false), false)
        }
    }

    func testContinuedViewingPreservesExplicitUnreadAndSuppressesUpdates() {
        for status in ["done", "failed", "blocked"] {
            XCTAssertNil(AgentUnread.change(for: pane(status, unread: true), previousStatus: status,
                                           reading: .viewing, manualRead: false))
            XCTAssertNil(AgentUnread.change(for: pane(status), previousStatus: "working",
                                           reading: .viewing, manualRead: false))
            XCTAssertEqual(AgentUnread.change(for: pane(status, unread: true), previousStatus: status,
                                             reading: .visiting, manualRead: false), false)
        }
    }

    func testExplicitReadEligibility() {
        for status: AgentStatus? in [.done, .failed, .blocked, .working, nil] {
            XCTAssertEqual(ReadChange.unread.applies(unread: false, status: status),
                           status == .done || status == .failed || status == .blocked)
            XCTAssertFalse(ReadChange.unread.applies(unread: true, status: status))
            XCTAssertTrue(ReadChange.read.applies(unread: true, status: status))
            XCTAssertFalse(ReadChange.read.applies(unread: false, status: status))
        }
    }

    func testInitialSnapshotAndExitedAgents() {
        for manualRead in [true, false] {
            XCTAssertNil(AgentUnread.change(for: pane("done"), previousStatus: nil, reading: .away, manualRead: manualRead))
            XCTAssertEqual(AgentUnread.change(for: pane("done", unread: true, command: "zsh"), previousStatus: "done",
                                              reading: .away, manualRead: manualRead), false)
        }
    }
}
