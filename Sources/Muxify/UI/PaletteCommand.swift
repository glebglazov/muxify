import AppKit
import MuxifyCore

enum PaletteCommand: String, CaseIterable {
    case newTopic = "New Topic"
    case movePane = "Move Pane"
    case moveWindow = "Move Window"
    case moveSession = "Move Session"
    case movePaneWithTab = "Move Pane with Active Tab"
    case addProject = "Add a Project"
    case snoozeTopic = "Snooze Topic"
    case settleTopic = "Settle Topic"
    case lockSession = "Lock Session"
    case unlockSession = "Unlock Session"
    case zen = "Zen"
    case endZen = "End Zen"
    case maximize = "Maximize"
    case restore = "Restore"
    case maximizeTerminal = "Maximize Terminal"
    case maximizeBrowser = "Maximize Browser"
    case focusTerminal = "Focus Terminal"
    case focusBrowser = "Focus Browser"
    case showSidebar = "Show Sidebar"
    case hideSidebar = "Hide Sidebar"
    case showTerminal = "Show Terminal"
    case hideTerminal = "Hide Terminal"
    case showBrowser = "Show Browser"
    case hideBrowser = "Hide Browser"
    case nextSession = "Show Next Session"
    case previousSession = "Show Previous Session"
    case nextTopic = "Show Next Topic"
    case previousTopic = "Show Previous Topic"
    case newAppWindow = "New Muxify Window"
    case newWindow = "New tmux Window"
    case newSession = "New tmux Session"
    case openConfig = "Open Config"
    case reloadConfig = "Reload Config"
    case installExtensions = "Install Extensions"
    case installCLI = "Install Command Line Tool"
    case newTab = "New Tab"
    case closeTab = "Close Tab"
    case openLocation = "Open Location"
    case nextTab = "Show Next Tab"
    case previousTab = "Show Previous Tab"
    case back = "Back"
    case forward = "Forward"
    case reloadPage = "Reload Page"
    case copyURL = "Copy URL"
    case developerTools = "Show Developer Tools"

    /// The keybinding that does what this Command does, so the row shows its shortcut.
    var keybinding: ConfigAction? {
        switch self {
        case .newTopic: .newTopic
        case .movePane: .movePane
        case .moveWindow: .moveWindow
        case .moveSession: .moveSession
        case .addProject: .addProjectToTopic
        case .snoozeTopic: .snoozeTopic
        case .settleTopic: .settleTopic
        case .zen, .endZen: .toggleZen
        case .lockSession, .unlockSession: .toggleLock
        case .newAppWindow: .newAppWindow
        case .maximize, .restore: .toggleMaximize
        case .maximizeTerminal: .toggleMaximizeTerminal
        case .maximizeBrowser: .toggleMaximizeBrowser
        case .focusTerminal: .focusTerminal
        case .focusBrowser: .focusBrowser
        case .showSidebar, .hideSidebar: .toggleSidebar
        case .showTerminal, .hideTerminal: .toggleTerminal
        case .showBrowser, .hideBrowser: .toggleBrowser
        case .nextSession: .selectNextSession
        case .previousSession: .selectPrevSession
        case .nextTopic: .selectNextTopic
        case .previousTopic: .selectPrevTopic
        default: nil
        }
    }

    /// Commands that change the layout or move Focus. They run as their
    /// keybinding does, after the palette gives Focus back.
    var isLayout: Bool {
        switch self {
        case .maximize, .restore, .maximizeTerminal, .maximizeBrowser, .focusTerminal, .focusBrowser,
             .showSidebar, .hideSidebar, .showTerminal, .hideTerminal, .showBrowser, .hideBrowser: true
        default: false
        }
    }
}

extension CommandPalette {
    var commands: [PaletteCommand] {
        guard let store else { return [] }
        let canChangeTopics = !store.isRemote && !store.changingTopic && store.topics.topicsEnabled
        let hasOpenTopic = store.topicWatcher.records.contains { $0.id == store.activeTopicID && $0.settledAt == nil }
        return PaletteCommand.allCases.filter { command in
            switch command {
            case .newTopic: return !store.isRemote && !store.changingTopic
            case .movePane, .moveWindow, .moveSession: return canChangeTopics && store.selectedWindow != nil
            case .movePaneWithTab: return canChangeTopics && store.selectedWindow != nil && store.currentBrowser?.activeTab != nil
            case .addProject, .snoozeTopic, .settleTopic: return canChangeTopics && hasOpenTopic
            case .lockSession, .unlockSession:
                guard canChangeTopics, let id = store.selectedWindow?.sessionID, let locked = store.lockState(ofSession: id) else { return false }
                return locked == (command == .unlockSession)
            case .zen: return canChangeTopics && hasOpenTopic && store.topicWatcher.zen == nil && store.topics.mode == .topics
            case .endZen: return !store.isRemote && !store.changingTopic && store.topicWatcher.zen != nil
            case .installExtensions: return !store.isRemote
            case .nextSession, .previousSession, .nextTopic, .previousTopic:
                guard let step = command.keybinding?.step else { return false }
                return store.stepTarget(step.level, step.direction) != nil
            case .closeTab, .nextTab, .previousTab: return store.currentBrowser?.activeTab != nil
            case .back: return store.currentBrowser?.activeTab?.canGoBack == true
            case .forward: return store.currentBrowser?.activeTab?.canGoForward == true
            case .reloadPage, .copyURL, .developerTools: return store.currentBrowser?.activeTab?.hasPage == true
            case .maximize: return store.panelLayout.maximized == nil && store.canToggleMaximize
            case .restore: return store.currentBrowser != nil && store.panelLayout.maximized != nil
            case .maximizeTerminal: return store.panelLayout.maximized != .terminal && store.canMaximize(.terminal)
            case .maximizeBrowser: return store.panelLayout.maximized != .browser && store.canMaximize(.browser)
            case .focusTerminal, .focusBrowser: return store.currentBrowser != nil
            case .showSidebar: return !store.sidebarShown
            case .hideSidebar: return store.sidebarShown
            case .showTerminal: return !store.panelLayout.shows(.terminal) && store.canToggle(.terminal)
            case .hideTerminal: return store.panelLayout.shows(.terminal) && store.canToggle(.terminal)
            case .showBrowser: return !store.panelLayout.shows(.browser) && store.canToggle(.browser)
            case .hideBrowser: return store.panelLayout.shows(.browser) && store.canToggle(.browser)
            default: return true
            }
        }
    }

    func shortcut(for command: PaletteCommand) -> String? {
        if let action = command.keybinding { return store?.config.keybinds.firstTrigger(for: action)?.symbol }
        switch command {
        case .newTab: return "⌘T"
        case .closeTab: return "⌘W"
        case .openLocation: return "⌘L"
        case .nextTab: return "⇧⌘]"
        case .previousTab: return "⇧⌘["
        case .back: return "⌘["
        case .forward: return "⌘]"
        case .reloadPage: return "⌘R"
        case .copyURL: return "⇧⌘C"
        case .developerTools: return "⌥⌘I"
        case .reloadConfig: return "⇧⌘,"
        default: return nil
        }
    }

    func run(_ command: PaletteCommand) {
        guard let store, commands.contains(command) else { return }
        if command.isLayout, let action = command.keybinding {
            close()
            // close() gives Focus back in a main-queue block; this one runs after it.
            DispatchQueue.main.async { store.perform(action) }
            return
        }
        switch command {
        case .newTopic, .movePane, .moveWindow, .moveSession, .movePaneWithTab, .addProject, .snoozeTopic, .settleTopic, .zen: break
        default: close(restoringFocus: false)
        }
        switch command {
        case .newTopic: store.presentNewTopic(keepingHistory: true)
        case .movePane: store.presentMovePane(nil, keepingHistory: true)
        case .movePaneWithTab: store.presentMovePane(nil, includesTab: true, keepingHistory: true)
        case .moveWindow: store.presentMoveWindow(keepingHistory: true)
        case .moveSession: store.presentMoveSession(keepingHistory: true)
        case .addProject: store.presentAddProject(keepingHistory: true)
        case .snoozeTopic: store.presentSnoozeTopic(keepingHistory: true)
        case .settleTopic: store.presentSettleTopic(keepingHistory: true)
        case .zen: store.toggleZenOfActiveTopic(keepingHistory: true)
        case .endZen: store.endZen()
        case .lockSession, .unlockSession: store.toggleLockOfCurrentSession()
        case .nextSession, .previousSession, .nextTopic, .previousTopic:
            if let step = command.keybinding?.step { store.step(step.level, step.direction) }
        case .newAppWindow: store.onNewAppWindow?()
        case .newWindow: store.newWindow()
        case .newSession: store.newSession()
        case .openConfig: store.openConfig()
        case .reloadConfig: store.reloadConfig()
        case .installExtensions: ExtensionInstaller.run()
        case .installCLI: CommandLineToolInstaller.run()
        case .newTab: store.browserCommand(opensBrowser: true) { $0.newTab() }
        case .closeTab: store.currentBrowser?.closeActiveTab()
        case .openLocation: store.browserCommand(opensBrowser: true) { _ in store.focusAddressBar() }
        case .nextTab: store.currentBrowser?.selectTab(offset: 1)
        case .previousTab: store.currentBrowser?.selectTab(offset: -1)
        case .back: store.currentBrowser?.activeTab?.goBack()
        case .forward: store.currentBrowser?.activeTab?.goForward()
        case .reloadPage: store.currentBrowser?.activeTab?.reloadOrStop()
        case .copyURL: store.currentBrowser?.activeTab?.copyURL()
        case .developerTools: store.currentBrowser?.activeTab?.showDeveloperTools()
        case .maximize, .restore, .maximizeTerminal, .maximizeBrowser, .focusTerminal, .focusBrowser,
             .showSidebar, .hideSidebar, .showTerminal, .hideTerminal, .showBrowser, .hideBrowser: break
        }
    }
}
