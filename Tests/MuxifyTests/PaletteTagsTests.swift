import XCTest
@testable import MuxifyCore

final class PaletteTagsTests: XCTestCase {
    private func tag(_ name: String) -> Tag { Tag(name: name)! }

    func testAHashWordMatchesOnlyTagsAndAnotherWordNeverMatchesATag() throws {
        let fields: [SearchField] = [.title("Fix reward drop"), .typeWord("topic"), .tag(tag("backend")), .tag(tag("release"))]
        let hash = try XCTUnwrap(FieldsMatch.best(FuzzyQuery("#ba"), in: fields))
        XCTAssertEqual(hash.positions, [2: [0, 1, 2]])
        XCTAssertNil(FieldsMatch.best(FuzzyQuery("#fix"), in: fields), "# does not match words in the title")
        XCTAssertNil(FieldsMatch.best(FuzzyQuery("backend"), in: fields), "a word without # does not match a Tag")
        XCTAssertNil(FieldsMatch.best(FuzzyQuery("#ba"), in: [.title("#backend notes")]))
        let tagged = FuzzyRanker.list([PickSectionInput(id: "s", rule: .ranked(showsWhenEmpty: true), candidates: [
            PickCandidate(id: "t", title: "Fix reward drop", fields: [.tag(tag("backend"))], pick: .available("t")),
            PickCandidate(id: "u", title: "Docs pass", pick: .available("u")),
            PickCandidate(id: "tag", title: "#backend", pick: .available("tag"), titlePlace: .tag),
        ])], query: FuzzyQuery("#ba"))
        XCTAssertEqual(tagged.rows.map(\.id), ["t", "tag"])
        XCTAssertEqual(tagged.rows[0].tags, [Highlighted(text: "#backend", marks: [0, 1, 2])], "the matched Tag shows after the title")
        XCTAssertEqual(tagged.rows[0].detail.text, "", "a Tag is not in the detail line")
        XCTAssertEqual(tagged.rows[1].title, Highlighted(text: "#backend", marks: [0, 1, 2]))
        XCTAssertEqual(tagged.rows[1].tags, [], "a Tag row's title is not repeated as a chip")
        let unmatched = FuzzyRanker.list([PickSectionInput(id: "s", rule: .ranked(showsWhenEmpty: true), candidates: [
            PickCandidate(id: "t", title: "Fix reward drop", fields: [.tag(tag("backend")), .tag(tag("release"))], pick: .available("t")),
        ])], query: FuzzyQuery(""))
        XCTAssertEqual(unmatched.rows[0].tags, [.plain("#backend"), .plain("#release")], "a Topic's Tags show with no query")
    }

    func testNewTopicTextKeepsTagWordsOutOfTheTitle() {
        let field = TagField(mode: .newTopic, chips: [tag("release")])
        let text = field.text("Fix #Backend reward #1 drop # #a.b #re")
        XCTAssertEqual(text.draft, "#re")
        XCTAssertEqual(text.title, "Fix reward drop # #a.b", "a # word that is not a Tag stays in the title")
        XCTAssertEqual(text.tags, [tag("release"), tag("backend"), tag("1"), tag("re")])
        XCTAssertEqual(text.refusedWords, [], "New Topic keeps a word that is not a Tag in the title")
        XCTAssertEqual(text.withoutDraft, "Fix #Backend reward #1 drop # #a.b ")
        XCTAssertNil(field.text("Fix #re ").draft, "a space after the word ends the draft")
        XCTAssertNil(field.text("Fix drop").draft)
        XCTAssertEqual(field.text("Fix #").draft, "#", "a lone # shows every Tag")
        XCTAssertEqual(field.text("#backend").title, "")
    }

    func testEditTagsTextTakesWordsWithoutHashAndRefusesTheWordsThatAreNotTags() {
        let field = TagField(mode: .editTags(TopicRecord(id: "t")), chips: [tag("ops")])
        let text = field.text("release #ops ba")
        XCTAssertEqual(text.draft, "#ba")
        XCTAssertEqual(text.tags, [tag("ops"), tag("release"), tag("ba")])
        XCTAssertEqual(text.withoutDraft, "release #ops ")
        XCTAssertEqual(field.text("ok a_b #c.d").refusedWords, ["a_b", "#c.d"])
        XCTAssertEqual(TagField(mode: .editTags(TopicRecord(id: "t"))).text("").tags, [])
    }

    @MainActor
    func testASpaceAfterACompleteTagWordMakesAChipThatBackspaceRemovesWhole() {
        let space = KeyTrigger(modifiers: [], key: .character(" "))
        let palette = CommandPalette()
        palette.begin(.text(.tags(TagField(mode: .newTopic))), text: "Fix #Backend")
        XCTAssertTrue(palette.handleFlow(space))
        XCTAssertEqual(palette.flow?.tagField?.chipField.chips, [tag("backend")])
        XCTAssertEqual(palette.query, "Fix ", "the chip takes the Tag word out of the field")
        for typed in ["Fix #a.b", "Fix #", "Fix ", "Fix drop"] {
            palette.query = typed
            XCTAssertFalse(palette.handleFlow(space), "\(typed): the space goes into the field")
            XCTAssertEqual(palette.flow?.tagField?.chipField.chips, [tag("backend")], typed)
        }

        palette.begin(.text(.tags(TagField(mode: .editTags(TopicRecord(id: "t")), chips: [tag("ops")]))), text: "QA")
        XCTAssertTrue(palette.handleFlow(space), "Edit Tags takes a word without #")
        XCTAssertEqual(palette.flow?.tagField?.chipField.chips, [tag("ops"), tag("qa")])
        XCTAssertEqual(palette.query, "")
        palette.back()
        XCTAssertEqual(palette.flow?.tagField?.chipField.chips, [tag("ops")], "⌫ in the empty field removes the new chip whole")
    }
}
