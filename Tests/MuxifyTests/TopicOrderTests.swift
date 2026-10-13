import XCTest
@testable import MuxifyCore

final class TopicOrderTests: XCTestCase {
    private func record(_ id: String, order: Double?) -> TopicRecord {
        var record = TopicRecord(id: id, title: id, slug: "untitled-" + id, homeProject: "/work/app")
        record.order = order
        record.createdAt = "1970-01-01T00:00:00Z"
        record.unknownFields = ["future": .object(["id": .string(id)])]
        record.sessions = [.object(["project_path": .string("/work/app"), "future_session": .integer(42)])]
        return record
    }

    private func applying(_ edits: [TopicListEntry], to entries: [TopicListEntry]) -> [TopicListEntry] {
        entries.map { entry in edits.first { $0.id == entry.id } ?? entry }
            + edits.filter { edit in !entries.contains { $0.id == edit.id } }
    }

    /// Each entry's Topic id, or `lock:` and its Session ID.
    private func ids(_ entries: [TopicListEntry]) -> [String] {
        entries.map {
            switch $0.id {
            case .topic(let id): return id
            case .lock(let sessionID): return "lock:" + sessionID
            }
        }
    }

    private func shown(_ entries: [TopicListEntry]) -> [String] { ids(TopicOrder.sorted(entries)) }

    func testDropPlacementFollowsTheHalfOfTheCardUnderTheDrag() {
        let frames = ["a": CGRect(x: 0, y: 0, width: 200, height: 40),
                      "b": CGRect(x: 0, y: 46, width: 200, height: 100),
                      "c": CGRect(x: 0, y: 152, width: 200, height: 40)]
        XCTAssertEqual(DropPlacement.at(60, frames: frames, dragging: "c"), .before("b"))
        XCTAssertEqual(DropPlacement.at(120, frames: frames, dragging: "c"), .after("b"))
        XCTAssertEqual(DropPlacement.at(43, frames: frames, dragging: "c"), .before("b"), "the gap above a card goes before it")
        XCTAssertEqual(DropPlacement.at(-10, frames: frames, dragging: "c"), .before("a"))
        XCTAssertEqual(DropPlacement.at(400, frames: frames, dragging: "a"), .after("c"), "below every card goes last")
        XCTAssertNil(DropPlacement.at(60, frames: frames, dragging: "b"), "a card dropped on itself stays")
        XCTAssertNil(DropPlacement.at(60, frames: [:], dragging: "b"))
    }

    func testMovesUseOnlyTheMovedRankWhenThereIsAFiniteGap() throws {
        let entries = [record("a", order: 0), record("b", order: 1), record("c", order: 2), record("d", order: 3)].map(TopicListEntry.topic)
        let cases: [(String, TopicPlacement, [String])] = [
            ("a", .after(.topic("d")), ["b", "c", "d", "a"]),
            ("d", .before(.topic("a")), ["d", "a", "b", "c"]),
            ("d", .after(.topic("b")), ["a", "b", "d", "c"]),
            ("a", .before(.topic("c")), ["b", "a", "c", "d"]),
        ]
        for (source, placement, expected) in cases {
            let edits = try TopicOrder.moving(.topic(source), to: placement, in: entries)
            XCTAssertEqual(ids(edits), [source])
            XCTAssertEqual(shown(applying(edits, to: entries)), expected)
            var original = entries.records.first { $0.id == source }!
            original.order = edits[0].order
            XCTAssertEqual(edits.records[0], original)
            XCTAssertTrue(edits[0].order!.isFinite)
        }
        XCTAssertTrue(try TopicOrder.moving(.topic("a"), to: .before(.topic("a")), in: entries).isEmpty)
        XCTAssertTrue(try TopicOrder.moving(.topic("a"), to: .before(.topic("b")), in: entries).isEmpty)
        XCTAssertTrue(try TopicOrder.moving(.topic("d"), to: .after(.topic("c")), in: entries).isEmpty)
    }

    func testEqualAbsentAndExhaustedRanksNormalizeOnlyOpenRecords() throws {
        let cases: [[Double?]] = [[0, 0, 0, 0], [nil, nil, nil, nil], [0, 1, Double(1).nextUp, 2]]
        for ranks in cases {
            let entries = zip(["a", "b", "c", "d"], ranks).map { TopicListEntry.topic(record($0, order: $1)) }
            let reordered = applying(try TopicOrder.moving(.topic("d"), to: .before(.topic("c")), in: entries), to: entries)
            XCTAssertEqual(shown(reordered), ["a", "b", "d", "c"])
            XCTAssertTrue(reordered.allSatisfy { $0.order?.isFinite == true })
            for old in entries.records {
                var expected = old
                expected.order = reordered.records.first { $0.id == old.id }!.order
                XCTAssertEqual(reordered.records.first { $0.id == old.id }, expected)
            }
        }
        var settled = record("settled", order: -100)
        settled.settledAt = "1970-01-01T00:00:00Z"
        var snoozed = record("b", order: 0)
        snoozed.snoozedUntil = "never"
        let entries = [record("a", order: 0), snoozed, record("c", order: 0), settled].map(TopicListEntry.topic)
        let edits = try TopicOrder.moving(.topic("c"), to: .before(.topic("b")), in: entries)
        XCTAssertEqual(shown(applying(edits, to: entries)), ["a", "c", "b"])
        XCTAssertFalse(ids(edits).contains("settled"))
        XCTAssertEqual(applying(edits, to: entries).records.first { $0.id == "settled" }, settled)
        XCTAssertThrowsError(try TopicOrder.moving(.topic("settled"), to: .before(.topic("a")), in: entries))
        XCTAssertThrowsError(try TopicOrder.moving(.topic("a"), to: .before(.topic("settled")), in: entries))
        XCTAssertThrowsError(try TopicOrder.moving(.topic("missing"), to: .before(.topic("a")), in: entries))
        XCTAssertThrowsError(try TopicOrder.moving(.topic("a"), to: .after(.topic("missing")), in: entries))
    }

    func testNewTopicIsFirstAfterMovesAndAtFiniteLimits() throws {
        let original = [record("a", order: 0), record("b", order: 1), record("c", order: 2)].map(TopicListEntry.topic)
        let moved = applying(try TopicOrder.moving(.topic("c"), to: .before(.topic("a")), in: original), to: original)
        let plan = TopicPlan(title: "New", project: Project(path: "/work/app", name: "app"),
                             records: moved.records, sessionNames: [], id: "new")
        let placed = applying(TopicOrder.inserting(plan.record, at: .top, in: moved), to: moved)
        XCTAssertEqual(shown(placed), ["new", "c", "a", "b"])
        let extreme = [record("a", order: -.greatestFiniteMagnitude), record("b", order: .greatestFiniteMagnitude)].map(TopicListEntry.topic)
        let inserted = applying(TopicOrder.inserting(record("new", order: nil), at: .top, in: extreme), to: extreme)
        XCTAssertEqual(shown(inserted), ["new", "a", "b"])
        XCTAssertTrue(inserted.allSatisfy { $0.order?.isFinite == true })
        let bottom = applying(try TopicOrder.moving(.topic("a"), to: .after(.topic("b")), in: extreme), to: extreme)
        XCTAssertEqual(shown(bottom), ["b", "a"])
        XCTAssertTrue(bottom.allSatisfy { $0.order?.isFinite == true })
    }

    func testALockGoesLastAmongTheUnpinnedEntriesAndMovesAsAnUnpinnedTopic() throws {
        var pinned = record("p", order: 9)
        pinned.isPinned = true
        let entries = [pinned, record("a", order: 0), record("b", order: 1)].map(TopicListEntry.topic)
            + [.lock(SessionLock(sessionID: "$1", order: 0.5))]
        XCTAssertEqual(shown(entries), ["p", "a", "lock:$1", "b"])
        let locked = applying(TopicOrder.appendingLock(of: "$2", in: entries), to: entries)
        XCTAssertEqual(shown(locked), ["p", "a", "lock:$1", "b", "lock:$2"])
        let moved = applying(try TopicOrder.moving(.lock(sessionID: "$2"), to: .before(.topic("p")), in: locked), to: locked)
        XCTAssertEqual(shown(moved), ["p", "lock:$2", "a", "lock:$1", "b"], "a Lock is never Pinned, so it stays below the Pinned Topics")
        let prepended = applying(TopicOrder.inserting(record("new", order: nil), at: .top, in: moved), to: moved)
        XCTAssertEqual(shown(prepended), ["p", "new", "lock:$2", "a", "lock:$1", "b"], "a new Topic goes before the Locks too")
    }

    func testARenumberGivesTheLocksTheirNewOrderToo() throws {
        let entries = [record("a", order: 0), record("b", order: Double(0).nextUp)].map(TopicListEntry.topic)
            + [.lock(SessionLock(sessionID: "$1", order: 2))]
        let edits = try TopicOrder.moving(.lock(sessionID: "$1"), to: .before(.topic("b")), in: entries)
        XCTAssertEqual(shown(applying(edits, to: entries)), ["a", "lock:$1", "b"])
        XCTAssertEqual(edits.locks.map(\.sessionID), ["$1"])
        XCTAssertTrue(edits.allSatisfy { $0.order?.isFinite == true })
    }
}
