import Foundation
import MuxifyCore

enum QuickSwitchSelection {
    case card(Int), window(Int), tab(Int)
}

extension ConfigAction {
    var quickSwitchSelection: QuickSwitchSelection? {
        switch self {
        case .selectCard1: .card(1)
        case .selectCard2: .card(2)
        case .selectCard3: .card(3)
        case .selectCard4: .card(4)
        case .selectCard5: .card(5)
        case .selectCard6: .card(6)
        case .selectCard7: .card(7)
        case .selectCard8: .card(8)
        case .selectCard9: .card(9)
        case .selectWindow1: .window(1)
        case .selectWindow2: .window(2)
        case .selectWindow3: .window(3)
        case .selectWindow4: .window(4)
        case .selectWindow5: .window(5)
        case .selectWindow6: .window(6)
        case .selectWindow7: .window(7)
        case .selectWindow8: .window(8)
        case .selectWindow9: .window(9)
        case .selectTab1: .tab(1)
        case .selectTab2: .tab(2)
        case .selectTab3: .tab(3)
        case .selectTab4: .tab(4)
        case .selectTab5: .tab(5)
        case .selectTab6: .tab(6)
        case .selectTab7: .tab(7)
        case .selectTab8: .tab(8)
        case .selectTab9: .tab(9)
        default: nil
        }
    }
}

enum QuickSwitchTarget: Hashable {
    /// `locked` is a Locked Session's card in Topics mode, by Session ID.
    case topic(String), locked(String), session(String), window(String), tab(UUID), terminal

    var accessibilityID: String {
        switch self {
        case .topic(let id): "hint-topic-" + id
        case .locked(let id): "hint-locked-" + id
        case .session(let id): "hint-session-" + id
        case .window(let id): "hint-window-" + id
        case .tab(let id): "hint-tab-" + id.uuidString
        case .terminal: "hint-terminal"
        }
    }
}

struct QuickSwitchTargets {
    let cards: [QuickSwitchTarget]
    let windows: [QuickSwitchTarget]
    let tabs: [QuickSwitchTarget]

    func target(for selection: QuickSwitchSelection) -> QuickSwitchTarget? {
        let targets: [QuickSwitchTarget]
        let position: Int
        switch selection {
        case .card(let value): targets = cards; position = value
        case .window(let value): targets = windows; position = value
        case .tab(let value): targets = tabs; position = value
        }
        guard (1...9).contains(position), position <= targets.count else { return nil }
        return targets[position - 1]
    }
}

extension QuickSwitchTargets {
    init(model: TopicsModel, sessions: [SessionGroup], windows: [TmuxWindow], tabIDs: [UUID]) {
        let cards: [QuickSwitchTarget]
        if model.mode == .topics {
            // No Topic Sessions get no number: the Topics list shows at most one of them, and only while it is open.
            // A Locked Session's card is numbered by its place among the Topics.
            cards = model.rows.compactMap { row in
                switch row.id {
                case .topic(let id): return .topic(id)
                case .locked(let id): return .locked(id)
                case .noTopic: return nil
                }
            }
        } else {
            cards = sessions.map { .session($0.id) }
        }
        self.init(cards: cards, windows: windows.map { .window($0.id) }, tabs: tabIDs.map { .tab($0) })
    }
}

extension WorkspaceStore {
    var quickSwitchWindows: [TmuxWindow] {
        guard let current = selectedWindow else { return [] }
        return windows.filter { $0.sessionID == current.sessionID }
    }

    var quickSwitchTargets: QuickSwitchTargets {
        QuickSwitchTargets(model: topics, sessions: sessions, windows: quickSwitchWindows,
                           tabIDs: currentBrowser?.tabs.map(\.id) ?? [])
    }

    var hintPresentation: HintPresentation {
        HintPresentation(modifiers: palette.isOpen ? nil : hintHold.visibleModifiers,
                         keybinds: config.keybinds, targets: quickSwitchTargets,
                         sidebar: sidebarShown && sessionsVisible,
                         browser: panelLayout.shows(.browser), terminal: surface != nil && panelLayout.shows(.terminal)
                            && topics.emptyTopic == nil && !topicSelection.showsEmptyNoTopic, config: config.hints)
    }

    func receiveHintInput(_ event: HintHoldState.Event) {
        hintHold.configure(delay: config.hints.holdDelay)
        hintHold.receive(event)
    }

    func quickSwitch(_ selection: QuickSwitchSelection) {
        guard let target = quickSwitchTargets.target(for: selection) else { return }
        switch target {
        case .topic(let id): goToTopic(.topic(id))
        case .locked(let id): goToTopic(.locked(id))
        case .session(let id): goToSession(id)
        case .window(let id):
            if let window = quickSwitchWindows.first(where: { $0.id == id }) { select(window) }
        case .tab(let id):
            if let browser = currentBrowser, let tab = browser.tabs.first(where: { $0.id == id }) {
                browser.jumpTo(tab)
            }
        case .terminal: focus(.terminal)
        }
    }
}
