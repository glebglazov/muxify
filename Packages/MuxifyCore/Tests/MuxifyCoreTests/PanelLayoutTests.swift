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

    func testMaximizeShowsOneSideAloneAndHidesTheSidebarUntilRestore() {
        var layout = PanelLayout(shown: .both)
        layout.toggleMaximize(.terminal, sidebarShown: true)
        XCTAssertEqual(onScreen(layout), [.terminal])
        XCTAssertTrue(layout.hidesSidebar)
        layout.toggleMaximize(.terminal, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
        XCTAssertFalse(layout.hidesSidebar)
    }

    func testMaximizeOfAHiddenBrowserShowsItAloneAndRestoreHidesItAgain() {
        var layout = PanelLayout()
        layout.toggleMaximize(.browser, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.browser])
        layout.restore()
        XCTAssertEqual(onScreen(layout), [.terminal])
    }

    func testMaximizingTheOtherSideStillRestoresTheToggles() {
        var layout = PanelLayout(shown: .both)
        layout.toggleMaximize(.browser, sidebarShown: true)
        layout.toggleMaximize(.terminal, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.terminal])
        XCTAssertTrue(layout.hidesSidebar)
        layout.toggleMaximize(.terminal, sidebarShown: false)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
    }

    func testAToggleWhileMaximizedKeepsWhatIsOnScreenThenApplies() {
        var layout = PanelLayout(shown: .both)
        layout.toggleMaximize(.browser, sidebarShown: true)
        XCTAssertFalse(layout.canToggle(.browser), "the Maximized side is the only side shown")
        layout.toggle(.browser)
        XCTAssertTrue(layout.hidesSidebar, "a disabled toggle restored the Window")

        layout.toggle(.terminal)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
        XCTAssertFalse(layout.hidesSidebar)

        var hidden = PanelLayout(shown: .both)
        hidden.toggleMaximize(.terminal, sidebarShown: true)
        hidden.commitMaximize()
        XCTAssertEqual(onScreen(hidden), [.terminal], "the side Maximize hid came back")
    }

    func testMaximizeWithNothingToHideDoesNothing() {
        var layout = PanelLayout(shown: .browser)
        XCTAssertFalse(layout.canMaximize(.browser, sidebarShown: false))
        layout.toggleMaximize(.browser, sidebarShown: false)
        XCTAssertFalse(layout.hidesSidebar)
        XCTAssertTrue(layout.canMaximize(.browser, sidebarShown: true), "Maximize can still hide the Sidebar")
        XCTAssertTrue(layout.canMaximize(.terminal, sidebarShown: false), "Maximize can swap the hidden side in")
    }

    func testClosingTheBrowserShowsTheTerminalAndRestoresAMaximizedBrowser() {
        var alone = PanelLayout(shown: .browser)
        alone.closeBrowser()
        XCTAssertEqual(onScreen(alone), [.terminal])

        var maximized = PanelLayout(shown: .both)
        maximized.toggleMaximize(.browser, sidebarShown: true)
        maximized.closeBrowser()
        XCTAssertEqual(onScreen(maximized), [.terminal])
        XCTAssertFalse(maximized.hidesSidebar)
    }

    func testShowingTheBrowserKeepsItAloneOrAddsItBesideTheTerminal() {
        var terminal = PanelLayout()
        terminal.show(.browser)
        XCTAssertEqual(onScreen(terminal), [.terminal, .browser])

        var browser = PanelLayout(shown: .browser)
        browser.show(.browser)
        XCTAssertEqual(onScreen(browser), [.browser])
    }

    func testRevealShowsAHiddenTerminalBesideTheBrowser() {
        var layout = PanelLayout(shown: .browser)
        layout.reveal(.terminal)
        XCTAssertEqual(onScreen(layout), [.terminal, .browser])
        XCTAssertNil(layout.maximized)
    }

    func testRevealOfTheBrowserRestoresAMaximizedTerminalAndShowsBothSides() {
        var hidden = PanelLayout(shown: .terminal, maximized: .terminal)
        hidden.reveal(.browser)
        XCTAssertNil(hidden.maximized, "the Maximized Terminal was not restored")
        XCTAssertEqual(onScreen(hidden), [.terminal, .browser])

        var both = PanelLayout(shown: .both, maximized: .terminal)
        both.reveal(.browser)
        XCTAssertNil(both.maximized)
        XCTAssertEqual(onScreen(both), [.terminal, .browser], "Restore did not give back the toggles")
    }

    func testRevealOfTheMaximizedSideKeepsItMaximized() {
        var layout = PanelLayout(shown: .both, maximized: .browser)
        layout.reveal(.browser)
        XCTAssertEqual(layout.maximized, .browser)
        XCTAssertEqual(onScreen(layout), [.browser])
    }
}
