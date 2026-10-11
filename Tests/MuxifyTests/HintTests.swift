import AppKit
import XCTest
@testable import MuxifyCore

final class HintTests: XCTestCase {
    func testDelayDuplicateEventsAndChangedModifiers() {
        var hold = HintHoldState()
        hold.receive(.modifiers(.control), at: 0)
        hold.receive(.modifiers(.control), at: 0.2)
        hold.advance(to: 0.349)
        XCTAssertNil(hold.visibleModifiers)
        hold.advance(to: 0.35)
        XCTAssertEqual(hold.visibleModifiers, .control)
        hold.receive(.modifiers([.control, .command]), at: 0.4)
        XCTAssertNil(hold.visibleModifiers)
        hold.advance(to: 0.749)
        XCTAssertNil(hold.visibleModifiers)
        hold.advance(to: 0.75)
        XCTAssertEqual(hold.visibleModifiers, [.control, .command])
        hold.receive(.modifiers(.command), at: 1)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.modifiers([]), at: 1.1)
        hold.advance(to: 10)
        XCTAssertNil(hold.visibleModifiers)
    }

    func testKeySuppressesPartialReleaseAndResetCancelsPendingTimer() {
        var hold = HintHoldState()
        hold.receive(.modifiers([.control, .command]), at: 0)
        hold.receive(.keyDown(18), at: 0.1)
        hold.receive(.keyUp(18), at: 0.2)
        hold.receive(.modifiers(.control), at: 0.3)
        hold.advance(to: 2)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.modifiers([]), at: 2)
        hold.receive(.modifiers(.control), at: 3)
        hold.receive(.reset, at: 3.1)
        hold.advance(to: 4)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.modifiers(.control), at: 5)
        hold.advance(to: 6)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.modifiers([]), at: 6)
        hold.receive(.modifiers(.option), at: 7)
        hold.advance(to: 7.35)
        XCTAssertEqual(hold.visibleModifiers, .option)
    }

    func testLetterHeldBeforeModifierPreventsHintsThroughModifierRelease() {
        var hold = HintHoldState()
        hold.receive(.keyDown(0), at: 0)
        hold.receive(.modifiers(.control), at: 0.1)
        hold.advance(to: 1)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.modifiers([]), at: 1)
        hold.receive(.modifiers(.command), at: 2)
        hold.advance(to: 3)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.keyUp(0), at: 3)
        hold.advance(to: 4)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.modifiers([]), at: 4)
        hold.receive(.modifiers(.command), at: 5)
        hold.advance(to: 6)
        XCTAssertEqual(hold.visibleModifiers, .command)
    }

    private func config(_ yaml: String) throws -> Config {
        try Config.load(path: "/config.yaml") { _ in yaml }.get()
    }

    private let targets = QuickSwitchTargets(cards: [.topic("first"), .session("second")],
                                             windows: [.window("@1"), .window("@2")], tabs: [.tab(UUID())])

    func testResolvedConfigClaimsAndRemapsSelectPositionNotPrintedDigit() throws {
        let config = try config("""
        keybindings:
          select_card_1: []
          select_card_2: [ctrl+7, ctrl+x, ctrl+cmd+2]
          select_window_1: ctrl+1
          move_keyboard_to_terminal: [ctrl+8, ctrl+t, alt+0]
        command_palettes:
          - name: Claimed
            keybinding: ctrl+3
            sources: windows
        """)
        let hints = HintPresentation(modifiers: .control, keybinds: config.keybinds, targets: targets,
                                     sidebar: true, browser: true, terminal: true)
        XCTAssertTrue(hints[.topic("first")].isEmpty)
        XCTAssertEqual(hints[.session("second")].map(\.symbol), ["⌃7", "⌃X"])
        XCTAssertEqual(hints[.window("@1")].map(\.symbol), ["⌃1"])
        XCTAssertEqual(hints[.terminal].map(\.symbol), ["⌃8"])
        XCTAssertNil(config.keybinds.action(for: try KeyTrigger("ctrl+3")))
        XCTAssertNil(config.keybinds.action(for: try KeyTrigger("ctrl+2")))
        XCTAssertEqual(config.keybinds.action(for: try KeyTrigger("ctrl+7")), .selectCard2)
        XCTAssertEqual(targets.target(for: .card(2)), .session("second"))
        let combined = HintPresentation(modifiers: [.control, .command], keybinds: config.keybinds, targets: targets,
                                       sidebar: true, browser: true, terminal: true)
        XCTAssertEqual(combined[.session("second")].map(\.symbol), ["⌃⌘2"])
        XCTAssertTrue(combined[.terminal].isEmpty)
    }

    func testHiddenPanelsAndMissingPositionsHaveNoHints() {
        for modifiers in [KeyTrigger.Modifiers.control, .option, .command] {
            let hints = HintPresentation(modifiers: modifiers, keybinds: .defaults, targets: targets,
                                         sidebar: false, browser: false, terminal: false)
            for target in targets.cards + targets.windows + targets.tabs + [.terminal] {
                XCTAssertTrue(hints[target].isEmpty)
            }
        }
        for position in [-1, 0, 3, 9, 10] { XCTAssertNil(targets.target(for: .card(position))) }
        let reordered = QuickSwitchTargets(cards: targets.cards.reversed(), windows: [], tabs: [])
        XCTAssertEqual(reordered.target(for: .card(1)), .session("second"))
    }

    func testHintsConfigDefaultsAndValidation() throws {
        let defaults = try config("").hints
        XCTAssertEqual(defaults.holdDelay, 0.35)
        XCTAssertTrue(defaults.cards.always && defaults.cards.hold)
        XCTAssertFalse(defaults.windows.always)
        XCTAssertTrue(defaults.windows.hold && defaults.tabs.always && defaults.tabs.hold && defaults.terminal.hold)
        for bad in ["true", "-1", ".inf", ".nan", "'0.2'", "null"] {
            let parsed = try config("hints: { hold_delay: \(bad) }")
            XCTAssertEqual(parsed.hints.holdDelay, 0.35, bad)
            XCTAssertEqual(parsed.problems.count, 1, bad)
        }
        let parsed = try config("hints: { hold_delay: false, cards: {always: false}, windows: {always: true}, tabs: {hold: false}, terminal: {always: true, hold: false} }")
        XCTAssertNil(parsed.hints.holdDelay)
        XCTAssertFalse(parsed.hints.cards.always)
        XCTAssertTrue(parsed.hints.windows.always)
        XCTAssertFalse(parsed.hints.tabs.hold)
        XCTAssertFalse(parsed.hints.terminal.hold)
        XCTAssertEqual(parsed.problems.count, 1)
        let remote = try Config.load(path: "/config.yaml", isRemote: true) { _ in "hints: {hold_delay: 0}" }.get()
        XCTAssertEqual(remote.hints.holdDelay, 0)
    }

    func testRestKeysUseFirstUsualModifierTriggerAndStopAtNine() throws {
        let config = try config("""
        hints:
          windows: {always: true}
        keybindings:
          select_card_1: [alt+j, ctrl+x, ctrl+y]
          select_window_1: ctrl+w
        """)
        let cards = (1...10).map { QuickSwitchTarget.topic(String($0)) }
        let targets = QuickSwitchTargets(cards: cards, windows: [.window("@1")], tabs: (1...10).map { _ in .tab(UUID()) })
        let hints = HintPresentation(modifiers: nil, keybinds: config.keybinds, targets: targets,
                                     sidebar: true, browser: true, terminal: true, config: config.hints)
        XCTAssertEqual(hints.restKey(for: cards[0]), "X")
        XCTAssertEqual(hints.restKey(for: cards[8]), "9")
        XCTAssertNil(hints.restKey(for: cards[9]))
        XCTAssertNil(hints.restKey(for: .window("@1")))
        XCTAssertEqual(hints.restKey(for: targets.tabs[8]), "9")
        XCTAssertNil(hints.restKey(for: targets.tabs[9]))
        XCTAssertNil(hints.restKey(for: .terminal))
        XCTAssertFalse(hints.sidebarActive)
    }

    func testSurfaceSwitchesDoNotRemoveShortcuts() throws {
        let config = try config("""
        hints:
          cards: {always: false, hold: false}
          windows: {always: false, hold: false}
          tabs: {always: false, hold: false}
          terminal: {hold: false}
        """)
        for modifiers in [KeyTrigger.Modifiers.control, .command, .option] {
            let hints = HintPresentation(modifiers: modifiers, keybinds: config.keybinds, targets: targets,
                                         sidebar: true, browser: true, terminal: true, config: config.hints)
            for target in targets.cards + targets.windows + targets.tabs + [.terminal] {
                XCTAssertNil(hints.restKey(for: target))
                XCTAssertTrue(hints[target].isEmpty)
            }
            XCTAssertFalse(hints.sidebarActive)
        }
        XCTAssertEqual(config.keybinds.action(for: try KeyTrigger("ctrl+1")), .selectCard1)
    }

    func testLiveDelayChangesAndDisabledHoldPreserveSuppression() {
        var hold = HintHoldState()
        hold.receive(.modifiers(.control), at: 0)
        hold.configure(delay: 0, at: 0.1)
        XCTAssertEqual(hold.visibleModifiers, .control)
        hold.configure(delay: nil, at: 0.2)
        XCTAssertNil(hold.visibleModifiers)
        hold.advance(to: 10)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.keyDown(0), at: 11)
        hold.receive(.keyUp(0), at: 12)
        hold.configure(delay: 0, at: 13)
        XCTAssertNil(hold.visibleModifiers)
        hold.receive(.modifiers([]), at: 14)
        hold.receive(.modifiers(.option), at: 15)
        XCTAssertEqual(hold.visibleModifiers, .option)
    }

    func testDefaultActionsAndTerminalMenuTrigger() throws {
        let config = try config("")
        for position in 1...9 {
            XCTAssertEqual(config.keybinds.action(for: try KeyTrigger("ctrl+\(position)")), ConfigAction(rawValue: "select_card_\(position)"))
            XCTAssertEqual(config.keybinds.action(for: try KeyTrigger("alt+\(position)")), ConfigAction(rawValue: "select_tab_\(position)"))
        }
        XCTAssertEqual(config.keybinds.firstTrigger(for: .moveKeyboardToTerminal), try KeyTrigger("ctrl+backquote"))
        for modifier in ["ctrl", "alt"] {
            XCTAssertEqual(config.keybinds.action(for: try KeyTrigger(modifier + "+0")), .moveKeyboardToTerminal)
        }
    }

    func testCardOrderIncludesPinnedDormantAndEveryNoTopicSession() {
        var pinned = TopicRecord(id: "pinned")
        pinned.isPinned = true
        let records = [TopicRecord(id: "dormant"), pinned]
        func window(_ id: String) -> TmuxWindow {
            TmuxWindow(id: "@" + id, sessionID: "$" + id, sessionName: "session-" + id, index: 0,
                       name: "shell", paneTitle: "shell", path: "/tmp", command: "zsh", isActive: true,
                       paneCount: 1, hasBell: false, sessionActivity: 0, agent: "", storedBrowser: .init(), openRequests: [])
        }
        let windows = [window("1"), window("2")]
        let sessions = windows.map { SessionGroup(id: $0.sessionID, name: $0.sessionName, windows: [$0]) }
        let topics = TopicsModel(records: records, windows: windows, config: Config(), selection: TopicSelection())
        XCTAssertNil(topics.openedNoTopicSession)
        let targets = QuickSwitchTargets(model: topics, sessions: sessions, windows: windows, tabIDs: [])
        XCTAssertEqual(targets.cards, [.topic("pinned"), .topic("dormant"), .session("$1"), .session("$2")])
        let sessionMode = TopicsModel(records: records, windows: windows, config: Config(),
                                      selection: TopicSelection(), mode: .sessions)
        XCTAssertEqual(QuickSwitchTargets(model: sessionMode, sessions: sessions.reversed(), windows: [], tabIDs: []).cards,
                       [.session("$2"), .session("$1")])
    }

    func testAppKitModifiersAndNumberedTriggerUseExactSet() throws {
        let flags: NSEvent.ModifierFlags = [.control, .option, .capsLock, .numericPad]
        XCTAssertEqual(KeyTrigger.Modifiers(flags), [.control, .option])
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.control, .shift], timestamp: 0, windowNumber: 0, context: nil,
            characters: "!", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18))
        let layout = try XCTUnwrap(KeyboardLayout(inputSourceID: "com.apple.keylayout.US"))
        XCTAssertEqual(KeyTrigger(event, layout: layout), try KeyTrigger("ctrl+shift+1"))
    }

    @MainActor
    func testTabJumpShowsHiddenBrowserAndRequestsKeyboard() throws {
        let browser = Browser(windowID: "@1", stored: StoredBrowser(
            tabURLs: ["https://one.test", "https://two.test"], layout: PanelLayout(shown: .terminal)))
        defer { browser.tearDown() }
        let tab = browser.tabs[1]
        browser.jumpTo(tab)
        XCTAssertTrue(browser.activeTab === tab)
        XCTAssertTrue(browser.layout.shows(.browser))
        XCTAssertEqual(browser.keyboardRequest, .page)
    }
}
