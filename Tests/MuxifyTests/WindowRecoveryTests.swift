import XCTest
@testable import MuxifyCore

final class WindowRecoveryTests: XCTestCase {
    func testClosedWindowReturnsToThePreviousWindowAcrossSessions() {
        var recovery = WindowRecovery()
        recovery.selected("@1")
        recovery.selected("@2")
        recovery.selected("@3")
        let windows = [window("@1"), window("@2", sessionID: "$2")]
        XCTAssertTrue(recovery.selectionDisappeared(in: windows))
        XCTAssertEqual(recovery.fallback(in: windows)?.id, "@2")
    }

    func testMissingPreviousWindowFallsBackToFirstSidebarWindow() {
        var recovery = WindowRecovery()
        recovery.selected("@2")
        recovery.selected("@3")
        XCTAssertEqual(recovery.fallback(in: [window("@4"), window("@1")])?.id, "@4")
    }

    func testEmptyServerHasNoRecoveryTarget() {
        var recovery = WindowRecovery()
        recovery.selected("@1")
        XCTAssertTrue(recovery.selectionDisappeared(in: []))
        XCTAssertNil(recovery.fallback(in: []))
    }

    func testRepeatedSnapshotsAndClearingSelectionDoNotOverwritePreviousWindow() {
        var recovery = WindowRecovery()
        recovery.selected("@1")
        recovery.selected("@2")
        recovery.selected("@2")
        recovery.selected(nil)
        XCTAssertEqual(recovery.previousWindowID, "@1")
        XCTAssertFalse(recovery.selectionDisappeared(in: [window("@2")]))
    }

    func testFreshEnvironmentOrServerCannotReuseSelectionHistory() {
        var recovery = WindowRecovery()
        recovery.selected("@1")
        recovery.selected("@2")
        recovery = WindowRecovery()
        XCTAssertNil(recovery.previousWindowID)
        XCTAssertFalse(recovery.selectionDisappeared(in: [window("@2")]))
    }

    func testOnlyConfirmedSessionAbsenceEnablesEmptyServerRecovery() {
        XCTAssertTrue(TmuxError.failed(status: 1, stderr: "no sessions").indicatesNoSessions)
        XCTAssertTrue(TmuxError.failed(status: 1, stderr: "no server running on /test/socket").indicatesNoSessions)
        XCTAssertTrue(TmuxError.failed(status: 1, stderr: "error connecting to /test/socket (No such file or directory)").indicatesNoSessions)
        for error in [TmuxError.timedOut, .notReady, .cancelled, .notInstalled,
                      .failed(status: 1, stderr: "error connecting to /test/socket (Permission denied)")] {
            XCTAssertFalse(error.indicatesNoSessions, error.description)
        }
    }

    private func window(_ id: String, sessionID: String = "$1") -> TmuxWindow {
        TmuxWindow(id: id, sessionID: sessionID, sessionName: "test", index: 0, name: "shell",
                   paneTitle: "", path: "/", command: "sh", isActive: true, paneCount: 1,
                   hasBell: false, sessionActivity: 0, agent: "", storedBrowser: StoredBrowser(), openRequests: [])
    }
}
