/// What a keybinding can do, with its default triggers.
public protocol KeybindAction: CaseIterable, Hashable, RawRepresentable where RawValue == String {
    /// The defaults as the user spells them, so the template can show them.
    static var defaultSpelling: KeyValuePairs<Self, [String]> { get }
    static var defaultTriggers: [Self: [KeyTrigger]] { get }
}

extension KeybindAction {
    static func parse(_ spelling: KeyValuePairs<Self, [String]>) -> [Self: [KeyTrigger]] {
        Dictionary(uniqueKeysWithValues: spelling.map { action, spellings in (action, spellings.map { try! KeyTrigger($0) }) })
    }
}

/// What a Muxify keybind can do, anywhere in an App Window.
public enum ConfigAction: String, KeybindAction {
    case newAppWindow = "new_app_window"
    case newTopic = "new_topic"
    case newTopicFromPane = "new_topic_from_pane"
    case moveSessionToTopic = "move_session_to_topic"
    case addProjectToTopic = "add_project_to_topic"
    case snoozeTopic = "snooze_topic"
    case zenMode = "zen_mode"
    case settleTopic = "settle_topic"
    case toggleSidebar = "toggle_sidebar"
    case toggleTerminal = "toggle_terminal"
    case toggleBrowser = "toggle_browser"
    case toggleFocus = "toggle_focus"
    case focusTerminal = "focus_terminal"
    case focusBrowser = "focus_browser"
    case moveKeyboardToTerminal = "move_keyboard_to_terminal"
    case selectCard1 = "select_card_1"
    case selectCard2 = "select_card_2"
    case selectCard3 = "select_card_3"
    case selectCard4 = "select_card_4"
    case selectCard5 = "select_card_5"
    case selectCard6 = "select_card_6"
    case selectCard7 = "select_card_7"
    case selectCard8 = "select_card_8"
    case selectCard9 = "select_card_9"
    case selectTab1 = "select_tab_1"
    case selectTab2 = "select_tab_2"
    case selectTab3 = "select_tab_3"
    case selectTab4 = "select_tab_4"
    case selectTab5 = "select_tab_5"
    case selectTab6 = "select_tab_6"
    case selectTab7 = "select_tab_7"
    case selectTab8 = "select_tab_8"
    case selectTab9 = "select_tab_9"
    case selectWindow1 = "select_window_1"
    case selectWindow2 = "select_window_2"
    case selectWindow3 = "select_window_3"
    case selectWindow4 = "select_window_4"
    case selectWindow5 = "select_window_5"
    case selectWindow6 = "select_window_6"
    case selectWindow7 = "select_window_7"
    case selectWindow8 = "select_window_8"
    case selectWindow9 = "select_window_9"
    case selectNextWindow = "select_next_window"
    case selectPrevWindow = "select_prev_window"

    public static let defaultSpelling: KeyValuePairs<ConfigAction, [String]> = [
        .newAppWindow: ["cmd+n"],
        .newTopic: [],
        .newTopicFromPane: ["cmd+shift+t"],
        .moveSessionToTopic: ["cmd+shift+m"],
        .addProjectToTopic: ["cmd+shift+a"],
        .settleTopic: [],
        .snoozeTopic: ["alt+cmd+s"],
        .zenMode: ["shift+alt+cmd+s"],
        .toggleSidebar: ["cmd+s", "ctrl+cmd+s"],
        .toggleTerminal: ["cmd+j"],
        .toggleBrowser: ["cmd+b"],
        .toggleFocus: ["shift+cmd+enter"],
        .focusTerminal: ["alt+cmd+t"],
        .focusBrowser: ["alt+cmd+b"],
        .moveKeyboardToTerminal: ["ctrl+backquote", "ctrl+0", "alt+0"],
        .selectCard1: ["ctrl+1"],
        .selectCard2: ["ctrl+2"],
        .selectCard3: ["ctrl+3"],
        .selectCard4: ["ctrl+4"],
        .selectCard5: ["ctrl+5"],
        .selectCard6: ["ctrl+6"],
        .selectCard7: ["ctrl+7"],
        .selectCard8: ["ctrl+8"],
        .selectCard9: ["ctrl+9"],
        .selectTab1: ["alt+1"],
        .selectTab2: ["alt+2"],
        .selectTab3: ["alt+3"],
        .selectTab4: ["alt+4"],
        .selectTab5: ["alt+5"],
        .selectTab6: ["alt+6"],
        .selectTab7: ["alt+7"],
        .selectTab8: ["alt+8"],
        .selectTab9: ["alt+9"],
        .selectWindow1: ["cmd+1"],
        .selectWindow2: ["cmd+2"],
        .selectWindow3: ["cmd+3"],
        .selectWindow4: ["cmd+4"],
        .selectWindow5: ["cmd+5"],
        .selectWindow6: ["cmd+6"],
        .selectWindow7: ["cmd+7"],
        .selectWindow8: ["cmd+8"],
        .selectWindow9: ["cmd+9"],
        .selectNextWindow: [],
        .selectPrevWindow: [],
    ]

    public static let defaultTriggers = parse(defaultSpelling)
}

/// What a keybind does while a Command Palette is open, from
/// `keybindings.command_palette`. These win over the other keybinds then.
public enum PaletteAction: String, KeybindAction {
    case jumpTo = "jump_to"
    case newSession = "new_session"
    case selectNext = "select_next"
    case selectPrev = "select_prev"
    case showActions = "show_actions"
    case copyPath = "copy_path"
    case copyTarget = "copy_target"
    case pastePath = "paste_path"
    case snooze

    case move
    case addProject = "add_project"
    case rename
    case suggest
    case zen
    case settle
    case forget
    case unsnooze
    case reopen
    case startFresh = "start_fresh"
    case pin
    case unpin
    case removeFromTopic = "remove_from_topic"
    case newWindow = "new_window"
    case reveal
    case killWindow = "kill_window"
    case movePane = "move_pane"
    case moveWindow = "move_window"
    case moveSession = "move_session"
    case includeTab = "include_tab"
    case newWorktree = "new_worktree"
    case suggestTitle = "suggest_title"

    public static let defaultSpelling: KeyValuePairs<PaletteAction, [String]> = [
        .jumpTo: ["enter"],
        .newSession: ["cmd+enter"],
        .selectNext: ["down", "ctrl+j"],
        .selectPrev: ["up", "ctrl+k"],
        .showActions: ["cmd+k"],
        .copyPath: ["cmd+c"],
        .copyTarget: ["cmd+shift+c"],
        .pastePath: ["ctrl+y"],
        .snooze: ["ctrl+s"],
        .move: [],
        .addProject: [],
        .rename: [],
        .suggest: [],
        .zen: [],
        .settle: [],
        .forget: [],
        .unsnooze: [],
        .reopen: [],
        .startFresh: [],
        .pin: [],
        .unpin: [],
        .removeFromTopic: [],
        .newWindow: [],
        .reveal: [],
        .killWindow: [],
        .movePane: ["alt+1"],
        .moveWindow: ["alt+2"],
        .moveSession: ["alt+3"],
        .includeTab: ["alt+t"],
        .newWorktree: ["alt+w"],
        .suggestTitle: ["alt+s"],
    ]

    public static let defaultTriggers = parse(defaultSpelling)
}

/// Each action's triggers, in the order they were listed. No trigger belongs
/// to two actions.
public struct KeybindSet<Action: KeybindAction>: Equatable {
    public let triggers: [Action: [KeyTrigger]]

    public init(triggers: [Action: [KeyTrigger]]) {
        self.triggers = triggers
    }

    public static var defaults: Self { Self(triggers: Action.defaultTriggers) }

    public func action(for trigger: KeyTrigger) -> Action? {
        triggers.first { $0.value.contains(trigger) }?.key
    }

    /// The trigger menus and tooltips show for `action`.
    public func firstTrigger(for action: Action) -> KeyTrigger? {
        triggers[action]?.first
    }
}

/// Muxify's keybinds that work throughout an App Window.
public typealias Keybinds = KeybindSet<ConfigAction>
/// The keybinds of an open Command Palette.
public typealias PaletteKeybinds = KeybindSet<PaletteAction>

extension KeybindSet where Action == ConfigAction {
    /// Remapping/disabling New App Window must also remove Ghostty's fallback
    /// Cmd+N behavior, rather than leaving a second shortcut in the terminal.
    public func suppressesDefaultAppWindowShortcut(_ trigger: KeyTrigger) -> Bool {
        trigger == Self.defaults.firstTrigger(for: .newAppWindow) && action(for: trigger) == nil
    }
}
