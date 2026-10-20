import XCTest
@testable import MuxifyCore

final class PaletteChipsTests: XCTestCase {
    private func tag(_ name: String) -> Tag { Tag(name: name)! }

    private func field(_ chips: [String], selection: Int? = nil) -> ChipField<String> {
        ChipField(chips: chips, selection: selection)
    }

    func testLeftAtTheTextStartSelectsTheLastChipAndLeftAndRightMoveTheSelection() {
        let abc = field(["a", "b", "c"])
        XCTAssertNil(abc.receiving(.left(caretAtStart: false)), "← inside the text moves the caret in the text")
        XCTAssertNil(field([]).receiving(.left(caretAtStart: true)), "with no chip, ← stays in the text")
        XCTAssertNil(abc.receiving(.right), "→ with the caret in the text moves the caret in the text")
        XCTAssertEqual(abc.receiving(.left(caretAtStart: true)), field(["a", "b", "c"], selection: 2))
        XCTAssertEqual(field(["a", "b", "c"], selection: 1).receiving(.left(caretAtStart: false)), field(["a", "b", "c"], selection: 0),
                       "← on a chip selects the chip to its left, wherever the caret was")
        XCTAssertEqual(field(["a", "b", "c"], selection: 0).receiving(.left(caretAtStart: false)), field(["a", "b", "c"], selection: 0),
                       "← on the first chip keeps it selected")
        XCTAssertEqual(field(["a", "b", "c"], selection: 1).receiving(.right), field(["a", "b", "c"], selection: 2))
        XCTAssertEqual(field(["a", "b", "c"], selection: 2).receiving(.right), abc, "→ after the last chip puts the caret back")
    }

    func testBackspaceOnAChipRemovesItAndSelectsTheChipToItsLeftElseTheCaret() {
        XCTAssertEqual(field(["a", "b", "c"], selection: 1).receiving(.deleteBackward(textIsEmpty: false)), field(["a", "c"], selection: 0))
        XCTAssertEqual(field(["a", "b", "c"], selection: 0).receiving(.deleteBackward(textIsEmpty: true)), field(["b", "c"]))
    }

    func testForwardDeleteOnAChipRemovesItAndSelectsTheChipToItsRightElseTheCaret() {
        XCTAssertEqual(field(["a", "b", "c"], selection: 1).receiving(.deleteForward), field(["a", "c"], selection: 1))
        XCTAssertEqual(field(["a", "b", "c"], selection: 2).receiving(.deleteForward), field(["a", "b"]))
        XCTAssertNil(field(["a", "b"]).receiving(.deleteForward), "⌦ with the caret in the text deletes in the text")
    }

    func testBackspaceWithTheCaretInAnEmptyTextRemovesTheLastChip() {
        XCTAssertEqual(field(["a", "b"]).receiving(.deleteBackward(textIsEmpty: true)), field(["a"]))
        XCTAssertNil(field(["a", "b"]).receiving(.deleteBackward(textIsEmpty: false)), "⌫ after text deletes a letter")
        XCTAssertNil(field([]).receiving(.deleteBackward(textIsEmpty: true)), "with no chip, ⌫ goes back one step")
    }

    func testALetterOnAChipPutsTheCaretBackInTheText() {
        XCTAssertEqual(field(["a", "b"], selection: 0).receiving(.toText), field(["a", "b"]))
        XCTAssertNil(field(["a", "b"]).receiving(.toText), "with the caret in the text, the text takes the letter")
    }

    func testOnlyPlainArrowsDeletesAndCharactersAreChipKeys() throws {
        func key(_ trigger: String) throws -> ChipKey? { ChipKey(try KeyTrigger(trigger), caretAtStart: true, textIsEmpty: true) }
        XCTAssertEqual(try key("left"), .left(caretAtStart: true))
        XCTAssertEqual(try key("right"), .right)
        XCTAssertEqual(try key("backspace"), .deleteBackward(textIsEmpty: true))
        XCTAssertEqual(try key("delete"), .deleteForward)
        XCTAssertEqual(try key("a"), .toText)
        XCTAssertEqual(try key("shift+a"), .toText)
        XCTAssertNil(try key("shift+left"), "⇧← extends the text selection")
        XCTAssertNil(try key("cmd+a"))
        XCTAssertNil(try key("down"))
        XCTAssertNil(try key("enter"))
    }

    @MainActor
    func testEditTagsChipKeysChangeTheChipsAndAnyTextChangePutsTheCaretBack() {
        let palette = CommandPalette()
        palette.begin(.text(.tags(TagField(mode: .editTags(TopicRecord(id: "t")), defined: ConfigTags(["ops", "qa", "ui"].map { TagDefinition(tag: Tag(name: $0)!) }), chips: [tag("ops"), tag("qa"), tag("ui")]))))
        XCTAssertTrue(palette.receiveChipKey(.left(caretAtStart: true)))
        XCTAssertTrue(palette.receiveChipKey(.left(caretAtStart: true)))
        XCTAssertEqual(palette.flow?.tagField?.chipField, ChipField(chips: [tag("ops"), tag("qa"), tag("ui")], selection: 1))
        XCTAssertTrue(palette.receiveChipKey(.deleteForward))
        XCTAssertEqual(palette.flow?.tagField?.chipField, ChipField(chips: [tag("ops"), tag("ui")], selection: 1))
        palette.query = "x"
        XCTAssertEqual(palette.flow?.tagField?.chipField, ChipField(chips: [tag("ops"), tag("ui")]), "typed text puts the caret back")
    }
}
