import XCTest
@testable import MuxifyCore

final class TagTests: XCTestCase {
    private var root: URL!
    private var paths: MuxifyPaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("muxify-tags-" + UUID().uuidString)
        paths = MuxifyPaths(environment: ["XDG_STATE_HOME": root.path], home: "/nonexistent")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func tags(_ names: String...) -> Set<Tag> { Set(names.map { Tag(name: $0)! }) }

    func testATagIsLowerCaseLettersDigitsAndDashAndTypedTextIsLowerCased() {
        XCTAssertEqual(Tag(typed: "#Backend")?.name, "backend")
        XCTAssertEqual(Tag(typed: "release-2")?.name, "release-2", "the # is optional")
        XCTAssertEqual(Tag(typed: "#Backend")?.description, "#backend")
        for typed in ["", "#", "##a", "back end", "back_end", "café", "a.b", "#a#b"] {
            XCTAssertNil(Tag(typed: typed), typed)
        }
        XCTAssertNil(Tag(name: "Backend"), "a record stores only the lower case form")
        XCTAssertNil(Tag(name: "#backend"), "a record stores the name without #")
    }

    private func written(_ id: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: paths.topics.appendingPathComponent(id + ".json")))
    }

    func testTheRecordKeepsTagsAsASortedArrayReadsTypedFormsAndKeepsUnknownFields() throws {
        let data = Data(##"{"id":"t","tags":["release","Backend","#ops","release"],"future":{"kept":true}}"##.utf8)
        let record = try JSONDecoder().decode(TopicRecord.self, from: data)
        XCTAssertEqual(record.tags, tags("backend", "ops", "release"))
        let store = TopicStore(paths: paths)
        try store.write { try $0.create(record) }
        try store.write { try $0.update("t") { $0.title = "Renamed" } }
        XCTAssertEqual(try written("t")["tags"], .array([.string("backend"), .string("ops"), .string("release")]))
        XCTAssertEqual(try written("t")["future"], .object(["kept": .bool(true)]))
        XCTAssertEqual(try store.read().records.first?.tags, tags("backend", "ops", "release"))

        try store.write { try $0.changeTags(of: "t", .set([])) }
        XCTAssertNil(try written("t")["tags"], "a Topic with no Tags has no tags key")
        XCTAssertEqual(try written("t")["title"], .string("Renamed"))
    }

    func testAWriteKeepsTagEntriesThatAreNotTagsAndATagChangeKeepsThemAfterTheTags() throws {
        try FileManager.default.createDirectory(at: paths.topics, withIntermediateDirectories: true)
        try Data(#"{"id":"t","tags":["release","",7,"a b",{"x":1}]}"#.utf8).write(to: paths.topics.appendingPathComponent("t.json"))
        let store = TopicStore(paths: paths)
        XCTAssertEqual(try store.read().records.first?.tags, tags("release"))
        let unreadable: [JSONValue] = [.string(""), .integer(7), .string("a b"), .object(["x": .integer(1)])]
        try store.write { try $0.update("t") { $0.title = "Renamed" } }
        XCTAssertEqual(try written("t")["tags"], .array([.string("release")] + unreadable), "a write of another field dropped them")
        try store.write { try $0.changeTags(of: "t", .set([Tag(name: "qa")!])) }
        XCTAssertEqual(try written("t")["tags"], .array([.string("qa")] + unreadable))
        try store.write { try $0.changeTags(of: "t", .set([])) }
        XCTAssertEqual(try written("t")["tags"], .array(unreadable), "removing every Tag dropped them")
    }

    func testAWriteKeepsATagsValueThatIsNotAnArrayUntilATagChangeSetsTags() throws {
        try FileManager.default.createDirectory(at: paths.topics, withIntermediateDirectories: true)
        try Data(#"{"id":"t","tags":"backend"}"#.utf8).write(to: paths.topics.appendingPathComponent("t.json"))
        let store = TopicStore(paths: paths)
        XCTAssertEqual(try store.read().records.first?.tags, [])
        try store.write { try $0.update("t") { $0.title = "Renamed" } }
        XCTAssertEqual(try written("t")["tags"], .string("backend"), "a write of another field dropped the value")
        try store.write { try $0.changeTags(of: "t", .add([Tag(name: "qa")!])) }
        XCTAssertEqual(try written("t")["tags"], .array([.string("qa")]))
    }

    func testAChangeAddsRemovesOrSetsAndOnlyAnOpenTopicChanges() throws {
        let store = TopicStore(paths: paths)
        var settled = TopicRecord(id: "done")
        settled.settledAt = "2026-01-01T00:00:00Z"
        try store.write {
            try $0.create(TopicRecord(id: "t"))
            try $0.create(settled)
        }
        func current() throws -> Set<Tag> { try XCTUnwrap(store.read().records.first { $0.id == "t" }).tags }
        try store.write { try $0.changeTags(of: "t", .add([Tag(name: "b")!, Tag(name: "a")!])) }
        XCTAssertEqual(try current(), tags("a", "b"))
        try store.write { try $0.changeTags(of: "t", .add([Tag(name: "a")!, Tag(name: "c")!])) }
        XCTAssertEqual(try current(), tags("a", "b", "c"))
        try store.write { try $0.changeTags(of: "t", .remove([Tag(name: "b")!, Tag(name: "z")!])) }
        XCTAssertEqual(try current(), tags("a", "c"))
        try store.write { try $0.changeTags(of: "t", .set([Tag(name: "x")!])) }
        XCTAssertEqual(try current(), tags("x"))
        XCTAssertThrowsError(try store.write { try $0.changeTags(of: "done", .add([Tag(name: "x")!])) })
        XCTAssertThrowsError(try store.write { try $0.changeTags(of: "missing", .add([Tag(name: "x")!])) })
        XCTAssertEqual(try store.read().records.first { $0.id == "done" }?.tags, [])
    }

    func testSuggestionsAreTheTagsOnTheRecordsNowSoForgetRemovesATagAndSettleKeepsIt() throws {
        let store = TopicStore(paths: paths)
        var only = TopicRecord(id: "only")
        only.tags = tags("research")
        var settled = TopicRecord(id: "settled")
        settled.tags = tags("writing", "backend")
        var open = TopicRecord(id: "open")
        open.tags = tags("backend")
        try store.write {
            try $0.create(only)
            try $0.create(settled)
            try $0.create(open)
        }
        try store.write { try $0.update("settled") { $0.settledAt = "2026-01-01T00:00:00Z" } }
        XCTAssertEqual(Tag.suggestions(from: try store.read().records).map(\.name), ["backend", "research", "writing"],
                       "A→Z, once each, and a Settled Topic keeps its Tags in the suggestions")
        try store.write { try $0.forget("only") }
        XCTAssertEqual(Tag.suggestions(from: try store.read().records).map(\.name), ["backend", "writing"],
                       "Forget of the last Topic with a Tag removes the Tag")
    }
}
