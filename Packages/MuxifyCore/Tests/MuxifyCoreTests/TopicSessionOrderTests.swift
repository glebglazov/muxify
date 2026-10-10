import XCTest
@testable import MuxifyCore

final class TopicSessionOrderTests: XCTestCase {
    private let projects = ["a", "b", "c", "d"].map { Project(path: "/work/" + $0, name: $0) }

    /// A live Session of the Topic in Project `name`, created at `created`.
    private func window(_ name: String, created: Int) -> TmuxWindow {
        TmuxWindow(id: "@" + name, sessionID: "$" + name, sessionName: name + "/topic", index: 0, name: "shell", paneTitle: "",
                   path: "/work/" + name, command: "zsh", isActive: true, paneCount: 1, hasBell: false, sessionActivity: 0,
                   agent: "", storedBrowser: StoredBrowser(), openRequests: [], topicID: "topic", sessionPath: "/work/" + name,
                   sessionCreated: created)
    }

    private func record(manual: [String]? = nil) -> TopicRecord {
        var record = TopicRecord(id: "topic", title: "Topic", slug: "topic", homeProject: "/work/a")
        if let manual {
            record.sessions = manual.map { .object(["project_path": .string("/work/" + $0)]) }
            record.hasManualSessionOrder = true
        }
        return record
    }

    private func names(_ windows: [TmuxWindow], record: TopicRecord, order: SessionOrder) -> [String] {
        TopicSessionOrder.ordered(windows, record: record, order: order) { TopicSessionKey(of: $0, record: record, projects: projects) }
            .map { String($0.sessionName.prefix { $0 != "/" }) }
    }

    private var live: [TmuxWindow] { [window("b", created: 200), window("a", created: 300), window("c", created: 100)] }

    func testWithoutAManualOrderSessionsFollowTheirCreationInTheConfigsOrder() {
        XCTAssertEqual(names(live, record: record(), order: .oldestFirst), ["c", "b", "a"])
        XCTAssertEqual(names(live, record: record(), order: .newestFirst), ["a", "b", "c"])
    }

    func testSessionsCreatedAtTheSameSecondFollowTheirSessionID() {
        let tied = [window("b", created: 100), window("a", created: 100)]
        XCTAssertEqual(names(tied, record: record(), order: .oldestFirst), ["a", "b"])
        XCTAssertEqual(names(tied, record: record(), order: .newestFirst), ["a", "b"])
    }

    func testAManualOrderKeepsTheRecordsOrderWhateverTheConfigSays() {
        let manual = record(manual: ["a", "c", "b"])
        XCTAssertEqual(names(live, record: manual, order: .oldestFirst), ["a", "c", "b"])
        XCTAssertEqual(names(live, record: manual, order: .newestFirst), ["a", "c", "b"])
    }

    func testANewSessionGoesToTheEndThatTheConfigsOrderGivesNewSessions() {
        let manual = record(manual: ["a", "c", "b"])
        let withNew = live + [window("d", created: 50)]
        XCTAssertEqual(names(withNew, record: manual, order: .oldestFirst), ["a", "c", "b", "d"])
        XCTAssertEqual(names(withNew, record: manual, order: .newestFirst), ["d", "a", "c", "b"])
    }

    func testRememberingKeepsAManualOrderAndANewSessionAtItsEnd() throws {
        let manual = record(manual: ["a", "c", "b"])
        let snapshot = TmuxSnapshot(windows: live + [window("d", created: 50)], clients: [], panes: [], serverRunning: true)
        let paths = { (record: TopicRecord) in record.sessions.compactMap { $0["project_path"]?.string } }
        let remembered = try XCTUnwrap(manual.remembering(snapshot, projects: projects, order: .newestFirst))
        XCTAssertEqual(paths(remembered), ["/work/d", "/work/a", "/work/c", "/work/b"])
        XCTAssertTrue(remembered.hasManualSessionOrder)
        XCTAssertNil(remembered.remembering(snapshot, projects: projects, order: .newestFirst), "a second read changes nothing")
    }

    func testRememberingWithoutAManualOrderKeepsTheSessionsOldestFirstForReopen() throws {
        let snapshot = TmuxSnapshot(windows: live, clients: [], panes: [], serverRunning: true)
        let remembered = try XCTUnwrap(record().remembering(snapshot, projects: projects, order: .newestFirst))
        XCTAssertEqual(remembered.sessions.compactMap { $0["project_path"]?.string }, ["/work/c", "/work/b", "/work/a"])
        XCTAssertFalse(remembered.hasManualSessionOrder)
    }

    func testTheManualOrderFlagSurvivesTheRecordFile() throws {
        let manual = record(manual: ["b", "a"])
        let text = String(decoding: try JSONEncoder().encode(manual), as: UTF8.self)
        XCTAssertTrue(text.contains(#""session_order":"manual""#), text)
        XCTAssertEqual(try JSONDecoder().decode(TopicRecord.self, from: Data(text.utf8)), manual)
        let automatic = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        XCTAssertFalse(automatic.contains("session_order"), automatic)
    }
}
