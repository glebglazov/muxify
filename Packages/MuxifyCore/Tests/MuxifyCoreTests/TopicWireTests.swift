import XCTest
@testable import MuxifyCore

/// The JSON of requests and responses is a contract with other processes, so each form is written out here.
final class TopicWireTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func assertRoundTrip<T: Codable & Equatable>(_ value: T, _ expected: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try json(value), expected, file: file, line: line)
        XCTAssertEqual(try JSONDecoder().decode(T.self, from: Data(expected.utf8)), value, file: file, line: line)
    }

    func testReviewedWindowAndPaneIDsRoundTripWithSessionChoices() throws {
        let choice = TopicSettleSession(id: "$1", name: "reviewed", disposition: .kill, worktree: nil,
                                        reviewedWindows: ["@1": ["%1", "%2"]])
        let data = try JSONEncoder().encode(choice)
        XCTAssertEqual(try JSONDecoder().decode(TopicSettleSession.self, from: data), choice)
        let old = Data(#"{"id":"$1","name":"reviewed","disposition":"kill","remove_worktree":false}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(TopicSettleSession.self, from: old).reviewedWindows)
    }

    func testSnoozeSendsItsTimeAsTheRecordStoresItAndItsTopicsAsAList() throws {
        try assertRoundTrip(TopicRequest(.snooze(until: .never), target: .window(try XCTUnwrap(WindowID(rawValue: "@4")))),
                            #"{"command":{"snooze":{"topics":[],"until":"never"}},"target":{"window":"@4"},"version":1}"#)
        try assertRoundTrip(TopicCommand.snooze(until: .at(Date(timeIntervalSince1970: 1_800_000_000)), topics: [.id("ship"), .named("Fix")]),
                            #"{"snooze":{"topics":[{"id":"ship"},{"named":"Fix"}],"until":"2027-01-15T08:00:00Z"}}"#)
        try assertRoundTrip(TopicCommand.unsnooze(topics: [.id("ship")]), #"{"unsnooze":{"topics":[{"id":"ship"}]}}"#)
        try assertRoundTrip(TopicResponse.snoozeChanged(TopicSnoozeChange(topicIDs: ["a", "b"], shortened: ["b"])),
                            #"{"snooze_changed":{"shortened":["b"],"topic_ids":["a","b"]}}"#)
        XCTAssertThrowsError(try JSONDecoder().decode(TopicCommand.self, from: Data(#"{"snooze":{"topics":[],"until":"soon"}}"#.utf8)))
    }

    func testExtractKeepsOldRequestsAndAddsAnOptionalTitle() throws {
        try assertRoundTrip(TopicCommand.extract(project: nil), #"{"extract":{}}"#)
        try assertRoundTrip(TopicCommand.extract(project: "/work/game"), #"{"extract":{"project":"/work/game"}}"#)
        try assertRoundTrip(TopicCommand.extract(project: nil, title: "Fix"), #"{"extract":{"title":"Fix"}}"#)
        try assertRoundTrip(TopicCommand.move(to: .newWindow(title: "Notes")), #"{"move":{"to":{"new_window":{"title":"Notes"}}}}"#)
    }

    func testConfirmationMembershipIsOptionalAndPreservesAnEmptyReview() throws {
        try assertRoundTrip(TopicRequest(.settle(choices: [], outcome: "Done"), expectedSessionIDs: ["$1"]),
                            #"{"command":{"settle":{"choices":[],"outcome":"Done"}},"expected_session_ids":["$1"],"version":1}"#)
        try assertRoundTrip(TopicRequest(.forget(choices: [], worktrees: []), expectedSessionIDs: []),
                            #"{"command":{"forget":{"choices":[],"worktrees":[]}},"expected_session_ids":[],"version":1}"#)
        let old = try JSONDecoder().decode(TopicRequest.self, from: Data(#"{"command":{"forget":{"choices":[],"worktrees":[]}},"version":1}"#.utf8))
        XCTAssertNil(old.expectedSessionIDs)
    }

    func testLockRequestsNameTheirSessionByName() throws {
        try assertRoundTrip(TopicRequest(.lock, target: .sessionName("notes")),
                            #"{"command":{"lock":{}},"target":{"session_name":"notes"},"version":1}"#)
        try assertRoundTrip(TopicRequest(.unlock, target: .session(SessionID(rawValue: "$3")!)),
                            #"{"command":{"unlock":{}},"target":{"session":"$3"},"version":1}"#)
    }

    func testRequests() throws {
        let pane = PaneID(rawValue: "%12")!
        try assertRoundTrip(TopicRequest(.forget(choices: [], worktrees: ["/trees/fix"]), target: .topic(.id("fix"))),
                            #"{"command":{"forget":{"choices":[],"worktrees":["/trees/fix"]}},"target":{"topic":{"id":"fix"}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.list), #"{"command":{"list":{}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.create(title: "Fix", project: "/work/game"), caller: .pane(pane)),
                            #"{"caller":{"pane":"%12"},"command":{"create":{"project":"/work/game","title":"Fix"}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.addProject(project: "/work/tools", workingCopy: .newWorktree(from: "/work/tools")),
                                         target: .topic(.id("fix"))),
                            #"{"command":{"add_project":{"project":"/work/tools","working_copy":{"new_worktree":{"from":"/work/tools"}}}},"target":{"topic":{"id":"fix"}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.addProject(project: "/work/tools", workingCopy: .newWorktree(from: "/work/tools", base: "origin/main")),
                                         target: .topic(.id("fix"))),
                            #"{"command":{"add_project":{"project":"/work/tools","working_copy":{"new_worktree":{"base":"origin/main","from":"/work/tools"}}}},"target":{"topic":{"id":"fix"}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.move(to: .topic(.named("Fix"))), target: .window(WindowID(rawValue: "@3")!), caller: .currentClient),
                            #"{"caller":{"current_client":true},"command":{"move":{"to":{"topic":{"ref":{"named":"Fix"}}}}},"target":{"window":"@3"},"version":1}"#)
        try assertRoundTrip(TopicRequest(.move(to: .newTopic(title: "New")), target: .session(SessionID(rawValue: "$4")!)),
                            #"{"command":{"move":{"to":{"new_topic":{"title":"New"}}}},"target":{"session":"$4"},"version":1}"#)
        let choice = TopicSettleSession(id: "$1", name: "game/fix", disposition: .kill,
                                        worktree: .init(projectPath: "/work/game", path: "/trees/fix", branch: "fix"), removeWorktree: true)
        try assertRoundTrip(TopicRequest(.settle(choices: [choice], outcome: "merged"), target: .pane(pane)),
                            #"{"command":{"settle":{"choices":[{"disposition":"kill","id":"$1","name":"game/fix","remove_worktree":true,"worktree":{"branch":"fix","path":"/trees/fix","project_path":"/work/game"}}],"outcome":"merged"}},"target":{"pane":"%12"},"version":1}"#)
        try assertRoundTrip(TopicRequest(.removeFromTopic, target: .pane(pane)),
                            #"{"command":{"remove_from_topic":{}},"target":{"pane":"%12"},"version":1}"#)
        try assertRoundTrip(TopicRequest(.removeAndKill(worktrees: ["/w/app/ship"]), target: .session(try XCTUnwrap(SessionID(rawValue: "$3")))),
                            #"{"command":{"remove_and_kill":{"worktrees":["/w/app/ship"]}},"target":{"session":"$3"},"version":1}"#)
        try assertRoundTrip(TopicRequest(.reopen, target: .topic(.id("fix"))),
                            #"{"command":{"reopen":{}},"target":{"topic":{"id":"fix"}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.show, target: .topic(.named("Fix"))),
                            #"{"command":{"show":{}},"target":{"topic":{"named":"Fix"}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.startFresh, target: .topic(.id("fix"))),
                            #"{"command":{"start_fresh":{}},"target":{"topic":{"id":"fix"}},"version":1}"#)
        try assertRoundTrip(TopicRequest(.moveSession(to: .before(SessionID(rawValue: "$2")!)), target: .session(SessionID(rawValue: "$4")!)),
                            #"{"command":{"move_session":{"to":{"before":{"session":"$2"}}}},"target":{"session":"$4"},"version":1}"#)
        try assertRoundTrip(TopicRequest(.sortSessions, target: .topic(.id("fix"))),
                            #"{"command":{"sort_sessions":{}},"target":{"topic":{"id":"fix"}},"version":1}"#)
    }

    func testResponses() throws {
        try assertRoundTrip(TopicResponse.topics([TopicSummary(id: "a", label: "Fix")]), #"{"topics":[{"id":"a","label":"Fix"}]}"#)
        try assertRoundTrip(TopicResponse.changed(TopicChange(topicID: "a", created: true, shown: .window(WindowID(rawValue: "@3")!))),
                            #"{"changed":{"created":true,"shown":{"window":{"id":"@3"}},"topic_id":"a"}}"#)
        try assertRoundTrip(TopicResponse.changed(TopicChange(topicID: "a", shown: .emptyTopic(id: "a"))),
                            #"{"changed":{"created":false,"shown":{"empty_topic":{"id":"a"}},"topic_id":"a"}}"#)
        let agent = TmuxPane(id: "%4", windowID: "@3", index: 1, title: "", path: "/work/game", command: "2.1.289",
                             agent: "claude", agentStatus: "", unread: false)
        let shell = TmuxPane(id: "%5", windowID: "@3", index: 2, isActive: true, title: "", path: "/work/game", command: "zsh",
                             agent: "claude", agentStatus: "done", unread: true)
        let window = TopicDetail.Window(id: "@3", index: 1, name: "zsh", active: true, panes: [PaneSummary(agent), PaneSummary(shell)])
        let session = TopicDetail.Session(id: "$2", name: "game/fix", project: .init(label: "game", path: "/work/game"),
                                          worktree: .init(path: "/trees/fix", branch: nil), windows: [window])
        try assertRoundTrip(TopicResponse.topic(TopicDetail(id: "a", label: "Fix", title: "Fix", slug: nil, homeProject: "/work/game",
                                                            createdAt: nil, snoozedUntil: nil, sessions: [session])),
                            #"{"topic":{"created_at":null,"home_project":"/work/game","id":"a","label":"Fix","sessions":[{"id":"$2","name":"game/fix","#
                            + #""project":{"label":"game","path":"/work/game"},"windows":[{"active":true,"id":"@3","index":1,"name":"zsh","panes":["#
                            + #"{"active":false,"agent":{"conversation":null,"kind":"claude","status":null,"unread":false},"command":"2.1.289","id":"%4","index":1,"label":"claude","path":"/work/game","window_id":"@3"},"#
                            + #"{"active":true,"agent":null,"command":"zsh","id":"%5","index":2,"label":"/w/game","path":"/work/game","window_id":"@3"}]}],"#
                            + #""worktree":{"base":null,"branch":null,"path":"/trees/fix"}}],"slug":null,"snoozed_until":null,"title":"Fix"}}"#)
        try assertRoundTrip(TopicResponse.failed(TopicFailure(kind: .storeBusy, phase: .recordSaved, message: "busy")),
                            #"{"failed":{"kind":"store_busy","message":"busy","phase":"record_saved"}}"#)
    }

    func testIDsAreParsedWhereTheyComeIn() {
        XCTAssertNil(PaneID(rawValue: "12"))
        XCTAssertNil(PaneID(rawValue: "%"))
        XCTAssertNil(WindowID(rawValue: "@x"))
        XCTAssertThrowsError(try JSONDecoder().decode(TopicTarget.self, from: Data(#"{"pane":"@3"}"#.utf8)))
        XCTAssertEqual(try JSONDecoder().decode(TopicFailure.Kind.self, from: Data(#""future_kind""#.utf8)).rawValue, "future_kind",
                       "an older reader keeps a kind it does not know")
    }

    func testANewerVersionIsRefusedAndChangesNothing() {
        var request = TopicRequest(.create(title: "Later", project: nil))
        request.version = TopicRequest.currentVersion + 1
        let paths = MuxifyPaths(environment: ["XDG_STATE_HOME": "/nonexistent/state"], home: "/nonexistent")
        guard case .failed(let failure) = TopicService(paths: paths).handle(request) else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.kind, .unsupported)
        XCTAssertEqual(failure.phase, .nothingChanged)
    }
}
