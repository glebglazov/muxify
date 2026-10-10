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

    private func applying(_ edits: [TopicRecord], to records: [TopicRecord]) -> [TopicRecord] {
        records.map { record in edits.first { $0.id == record.id } ?? record }
            + edits.filter { edit in !records.contains { $0.id == edit.id } }
    }

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
        let records = [record("a", order: 0), record("b", order: 1), record("c", order: 2), record("d", order: 3)]
        let cases: [(String, TopicPlacement, [String])] = [
            ("a", .after("d"), ["b", "c", "d", "a"]),
            ("d", .before("a"), ["d", "a", "b", "c"]),
            ("d", .after("b"), ["a", "b", "d", "c"]),
            ("a", .before("c"), ["b", "a", "c", "d"]),
        ]
        for (source, placement, ids) in cases {
            let edits = try TopicOrder.moving(source, to: placement, in: records)
            XCTAssertEqual(edits.map(\.id), [source])
            XCTAssertEqual(TopicOrder.sorted(applying(edits, to: records)).map(\.id), ids)
            var original = records.first { $0.id == source }!
            original.order = edits[0].order
            XCTAssertEqual(edits[0], original)
            XCTAssertTrue(edits[0].order!.isFinite)
        }
        XCTAssertTrue(try TopicOrder.moving("a", to: .before("a"), in: records).isEmpty)
        XCTAssertTrue(try TopicOrder.moving("a", to: .before("b"), in: records).isEmpty)
        XCTAssertTrue(try TopicOrder.moving("d", to: .after("c"), in: records).isEmpty)
    }

    func testEqualAbsentAndExhaustedRanksNormalizeOnlyOpenRecords() throws {
        let cases: [[Double?]] = [[0, 0, 0, 0], [nil, nil, nil, nil], [0, 1, Double(1).nextUp, 2]]
        for ranks in cases {
            let records = zip(["a", "b", "c", "d"], ranks).map { record($0, order: $1) }
            let edits = try TopicOrder.moving("d", to: .before("c"), in: records)
            let reordered = applying(edits, to: records)
            XCTAssertEqual(TopicOrder.sorted(reordered).map(\.id), ["a", "b", "d", "c"])
            XCTAssertTrue(reordered.allSatisfy { $0.order?.isFinite == true })
            for old in records {
                var expected = old
                expected.order = reordered.first { $0.id == old.id }!.order
                XCTAssertEqual(reordered.first { $0.id == old.id }, expected)
            }
        }
        var settled = record("settled", order: -100)
        settled.settledAt = "1970-01-01T00:00:00Z"
        var snoozed = record("b", order: 0)
        snoozed.snoozedUntil = "never"
        let records = [record("a", order: 0), snoozed, record("c", order: 0), settled]
        let edits = try TopicOrder.moving("c", to: .before("b"), in: records)
        XCTAssertEqual(TopicOrder.sorted(applying(edits, to: records)).map(\.id), ["a", "c", "b"])
        XCTAssertFalse(edits.contains { $0.id == "settled" })
        XCTAssertEqual(applying(edits, to: records).first { $0.id == "settled" }, settled)
        XCTAssertThrowsError(try TopicOrder.moving("settled", to: .before("a"), in: records))
        XCTAssertThrowsError(try TopicOrder.moving("a", to: .before("settled"), in: records))
        XCTAssertThrowsError(try TopicOrder.moving("missing", to: .before("a"), in: records))
        XCTAssertThrowsError(try TopicOrder.moving("a", to: .after("missing"), in: records))
    }

    func testNewTopicIsFirstAfterMovesAndAtFiniteLimits() throws {
        let original = [record("a", order: 0), record("b", order: 1), record("c", order: 2)]
        let moved = applying(try TopicOrder.moving("c", to: .before("a"), in: original), to: original)
        let plan = TopicPlan(title: "New", project: Project(path: "/work/app", name: "app"),
                             records: moved, sessionNames: [], id: "new")
        XCTAssertEqual(TopicOrder.sorted(moved + [plan.record]).map(\.id), ["new", "c", "a", "b"])
        let extreme = [record("a", order: -.greatestFiniteMagnitude), record("b", order: .greatestFiniteMagnitude)]
        let inserted = applying(TopicOrder.prepending(record("new", order: nil), in: extreme), to: extreme)
        XCTAssertEqual(TopicOrder.sorted(inserted).map(\.id), ["new", "a", "b"])
        XCTAssertTrue(inserted.allSatisfy { $0.order?.isFinite == true })
        let bottom = applying(try TopicOrder.moving("a", to: .after("b"), in: extreme), to: extreme)
        XCTAssertEqual(TopicOrder.sorted(bottom).map(\.id), ["b", "a"])
        XCTAssertTrue(bottom.allSatisfy { $0.order?.isFinite == true })
    }
}
