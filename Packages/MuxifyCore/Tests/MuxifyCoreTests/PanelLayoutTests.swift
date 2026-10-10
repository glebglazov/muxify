import XCTest
import MuxifyCore

final class PanelLayoutTests: XCTestCase {
    private func onScreen(_ layout: PanelLayout) -> [PanelLayout.Side] {
        [.terminal, .browser].filter(layout.shows)
    }

    func testTogglesShowAndHideEachSideButNeverBoth() {
        var layout = PanelLayout(shown: .both)
        layout.toggle(.terminal)
        XCTAssertEqual(onScreen(layout), [.browser])
        XCTAssertFalse(layout.canToggle(.browser))
        layout.toggle(.browser)
        XCTAssertEqual(onScreen(layout), [.browser], "the only side shown was hidden")
        layout.toggle(.terminal)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
    }

    func testFocusShowsOneSideAloneAndHidesTheSidebarUntilItEnds() {
        var layout = PanelLayout(shown: .both)
        layout.toggleFocus(.terminal, sidebarShown: true)
        XCTAssertEqual(onScreen(layout), [.terminal])
        XCTAssertTrue(layout.hidesSidebar)
        layout.toggleFocus(.terminal, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
        XCTAssertFalse(layout.hidesSidebar)
    }

    func testFocusOnAHiddenBrowserShowsItAloneAndEndingFocusHidesItAgain() {
        var layout = PanelLayout()
        layout.toggleFocus(.browser, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.browser])
        layout.endFocus()
        XCTAssertEqual(onScreen(layout), [.terminal])
    }

    func testMovingFocusToTheOtherSideStillRestoresTheToggles() {
        var layout = PanelLayout(shown: .both)
        layout.toggleFocus(.browser, sidebarShown: true)
        layout.toggleFocus(.terminal, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.terminal])
        XCTAssertTrue(layout.hidesSidebar)
        layout.toggleFocus(.terminal, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
    }

    func testAToggleDuringFocusKeepsWhatIsOnScreenThenApplies() {
        var layout = PanelLayout(shown: .both)
        layout.toggleFocus(.browser, sidebarShown: true)
        XCTAssertFalse(layout.canToggle(.browser), "the side in Focus is the only side shown")
        layout.toggle(.browser)
        XCTAssertTrue(layout.hidesSidebar, "a disabled toggle ended Focus")

        layout.toggle(.terminal)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
        XCTAssertFalse(layout.hidesSidebar)

        var hidden = PanelLayout(shown: .both)
        hidden.toggleFocus(.terminal, sidebarShown: true)
        hidden.commitFocus()
        XCTAssertEqual(onScreen(hidden), [.terminal], "the side Focus hid came back")
    }

    func testFocusWithNothingToHideDoesNothing() {
        var layout = PanelLayout(shown: .browser)
        XCTAssertFalse(layout.canFocus(.browser, sidebarShown: false))
        layout.toggleFocus(.browser, sidebarShown: false)
        XCTAssertFalse(layout.hidesSidebar)
        XCTAssertTrue(layout.canFocus(.browser, sidebarShown: true), "Focus can still hide the Sidebar")
        XCTAssertTrue(layout.canFocus(.terminal, sidebarShown: false), "Focus can swap the hidden side in")
    }

    func testClosingTheBrowserShowsTheTerminalAndEndsBrowserFocus() {
        var alone = PanelLayout(shown: .browser)
        alone.closeBrowser()
        XCTAssertEqual(onScreen(alone), [.terminal])

        var focused = PanelLayout(shown: .both)
        focused.toggleFocus(.browser, sidebarShown: true)
        focused.closeBrowser()
        XCTAssertEqual(onScreen(focused), [.terminal])
        XCTAssertFalse(focused.hidesSidebar)
    }

    func testShowingTheBrowserKeepsItAloneOrAddsItBesideTheTerminal() {
        var terminal = PanelLayout()
        terminal.show(.browser)
        XCTAssertEqual(onScreen(terminal), [.terminal, .browser])

        var browser = PanelLayout(shown: .browser)
        browser.show(.browser)
        XCTAssertEqual(onScreen(browser), [.browser])
    }
}
