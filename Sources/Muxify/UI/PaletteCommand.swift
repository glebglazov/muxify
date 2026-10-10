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
    case zen = "Zen"
    case endZen = "End Zen"
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
            case .zen: return canChangeTopics && hasOpenTopic && store.topicWatcher.zen == nil
            case .endZen: return !store.isRemote && !store.changingTopic && store.topicWatcher.zen != nil
            case .installExtensions: return !store.isRemote
            case .closeTab, .nextTab, .previousTab: return store.currentBrowser?.activeTab != nil
            case .back: return store.currentBrowser?.activeTab?.canGoBack == true
            case .forward: return store.currentBrowser?.activeTab?.canGoForward == true
            case .reloadPage, .copyURL, .developerTools: return store.currentBrowser?.activeTab?.hasPage == true
            default: return true
            }
        }
    }

    func shortcut(for command: PaletteCommand) -> String? {
        switch command {
        case .newTopic: return store?.config.keybinds.firstTrigger(for: .newTopic)?.symbol
        case .movePane: return store?.config.keybinds.firstTrigger(for: .newTopicFromPane)?.symbol
        case .moveSession: return store?.config.keybinds.firstTrigger(for: .moveSessionToTopic)?.symbol
        case .addProject: return store?.config.keybinds.firstTrigger(for: .addProjectToTopic)?.symbol
        case .snoozeTopic: return store?.config.keybinds.firstTrigger(for: .snoozeTopic)?.symbol
        case .settleTopic: return store?.config.keybinds.firstTrigger(for: .settleTopic)?.symbol
        case .zen, .endZen: return store?.config.keybinds.firstTrigger(for: .zenMode)?.symbol
        case .newAppWindow: return store?.config.keybinds.firstTrigger(for: .newAppWindow)?.symbol
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
        switch command {
        case .newTopic, .movePane, .moveWindow, .moveSession, .movePaneWithTab, .addProject, .snoozeTopic, .settleTopic, .zen: break
        default: close(restoringFocus: false)
        }
        switch command {
        case .newTopic: store.presentNewTopic(keepingHistory: true)
        case .movePane: store.newTopicFromPane(nil, keepingHistory: true)
        case .movePaneWithTab: store.newTopicFromPane(nil, includesTab: true, keepingHistory: true)
        case .moveWindow:
            if let window = store.selectedWindow { openMove(window, scope: .window, keepingHistory: true) }
        case .moveSession: store.presentMoveSession(keepingHistory: true)
        case .addProject: store.presentAddProject(keepingHistory: true)
        case .snoozeTopic: store.presentSnoozeTopic(keepingHistory: true)
        case .settleTopic: store.presentSettleTopic(keepingHistory: true)
        case .zen: store.toggleZenOfActiveTopic(keepingHistory: true)
        case .endZen: store.endZen()
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
        }
    }
}
