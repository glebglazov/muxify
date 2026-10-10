import XCTest
@testable import MuxifyCore

final class TopicRequestURLTests: XCTestCase {
    private func request(_ string: String) throws -> TopicRequest {
        try TopicRequest(url: try XCTUnwrap(URL(string: string)))
    }

    private let pane7 = TopicTarget.pane(PaneID(rawValue: "%7")!)

    func testTitledNewUsesExplicitProjectOrPane() throws {
        XCTAssertEqual(try request("muxify://topic/new?title=Fix%20reward&project=%2Fwork%2Fgame"),
                       TopicRequest(.create(title: "Fix reward", project: "/work/game")))
        XCTAssertEqual(try request("muxify://topic/new?pane=%257&title=%20Caf%C3%A9%20"),
                       TopicRequest(.create(title: "Café", project: nil), target: pane7))
        XCTAssertEqual(try request("muxify://topic/new?pane=%257&title=Fix&project=%2Fwork%2Fgame"),
                       TopicRequest(.create(title: "Fix", project: "/work/game")))
    }

    func testUntitledNewExtractsPaneWithOptionalHomeProject() throws {
        XCTAssertEqual(try request("muxify://topic/new?pane=%257"), TopicRequest(.extract(project: nil), target: pane7))
        XCTAssertEqual(try request("muxify://topic/new?pane=%257&project=%2Fwork%2Fgame"),
                       TopicRequest(.extract(project: "/work/game"), target: pane7))
    }

    func testForgetNamesATopicOrPane() throws {
        XCTAssertEqual(try request("muxify://topic/forget?pane=%257"), TopicRequest(.forget(choices: [], worktrees: []), target: pane7))
        XCTAssertEqual(try request("muxify://topic/forget?topic=settled"),
                       TopicRequest(.forget(choices: [], worktrees: []), target: .topic(.named("settled"))))
        XCTAssertThrowsError(try request("muxify://topic/forget?topic=settled&pane=%257"))
    }

    func testMembershipAndLifecycleRequests() throws {
        XCTAssertEqual(try request("muxify://topic/add?pane=%257&project=%2Fwork%2Ftools"),
                       TopicRequest(.addProject(project: "/work/tools", workingCopy: .project), target: pane7))
        XCTAssertEqual(try request("muxify://topic/settle?pane=%257"), TopicRequest(.settle(choices: [], outcome: ""), target: pane7))
        XCTAssertEqual(try request("muxify://topic/move?pane=%257&topic=Fix%20reward"),
                       TopicRequest(.move(to: .topic(.named("Fix reward"))), target: pane7))
    }

    func testRejectsMissingDuplicateAndUnknownInputs() {
        let invalid = [
            "muxify://topic/new?title=Fix", "muxify://topic/new?project=%2Fwork&pane=%257&title=",
            "muxify://topic/new?pane=%257&title=%20", "muxify://topic/add?pane=%257",
            "muxify://topic/settle", "muxify://topic/move?pane=%257&topic=",
            "muxify://topic/settle?pane=%257&pane=%257", "muxify://topic/settle?pane=%257&pane=%258",
            "muxify://topic/add?pane=%257&project=relative", "muxify://topic/add?pane=%257&project=%2Fwork&extra=x",
            "muxify://topic/move?pane=7&topic=fix", "muxify://topic/new?pane=%25x",
            "muxify://topic/new?pane=%257&project=%2Fwork&project=%2Fwork",
            "muxify://topic/new?pane=%257&title=Fix&project=%2Fwork&extra=x",
        ]
        for value in invalid {
            XCTAssertThrowsError(try request(value), value)
        }
    }

    func testRejectsOtherURLShapes() {
        let invalid = [
            "other://topic/new?pane=%257", "muxify://other/new?pane=%257",
            "muxify://topic/new/other?pane=%257", "muxify://topic/new/?pane=%257",
            "muxify://topic/list?pane=%257", "muxify://topic/new?pane=%257#part",
            "muxify://user@topic/new?pane=%257", "muxify://topic:123/new?pane=%257",
            "muxify://topic/new", "muxify://topic/settle?pane=%257&topic=fix",
        ]
        for value in invalid { XCTAssertThrowsError(try request(value), value) }
    }
}
