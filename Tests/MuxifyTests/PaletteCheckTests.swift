import XCTest
@testable import MuxifyCore

final class PaletteCheckTests: XCTestCase {
    private let backend = CheckRow.tag(Tag(name: "backend")!, topics: ["a", "b", "c"])

    func testReturnWithTopicsCheckedGoesOnWithThemOnAnyRow() {
        XCTAssertEqual(CheckRow.topic("z").returnOutcome(checked: ["a", "b"]), .goOn(["a", "b"]), "not with the highlighted Topic")
        XCTAssertEqual(backend.returnOutcome(checked: ["z"]), .goOn(["z"]), "not with the Topics of the highlighted Tag")
    }

    func testReturnWithNothingCheckedGoesOnWithTheTopicOrChecksTheTagAndStays() {
        XCTAssertEqual(CheckRow.topic("z").returnOutcome(checked: []), .goOn(["z"]))
        XCTAssertEqual(backend.returnOutcome(checked: []), .check(["a", "b", "c"]), "↩ by reflex on a Tag never goes on")
    }

    func testATagBoxComesFromHowManyOfItsTopicsAreChecked() {
        XCTAssertEqual(backend.box(checked: ["z"]), .none)
        XCTAssertEqual(backend.box(checked: ["a", "z"]), .some)
        XCTAssertEqual(backend.box(checked: ["a", "b", "c", "z"]), .all)
        XCTAssertEqual(CheckRow.topic("a").box(checked: ["a"]), .all)
        XCTAssertEqual(CheckRow.topic("a").box(checked: ["b"]), .none)
    }

    func testSpaceOnATagChecksAllItsTopicsUnlessAllAreCheckedThenUnchecksThem() {
        var draft = CheckDraft(action: .snooze, checked: ["a", "z"])
        draft.flip(backend.topics)
        XCTAssertEqual(draft.checked, ["a", "b", "c", "z"], "some checked: Space checks all")
        draft.flip(backend.topics)
        XCTAssertEqual(draft.checked, ["z"], "all checked: Space unchecks all, and keeps the other Topics")
        draft.flip(CheckRow.topic("z").topics)
        XCTAssertEqual(draft.checked, [])
    }
}
