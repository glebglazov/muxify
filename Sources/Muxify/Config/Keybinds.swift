/// What a Muxify keybind can do.
enum ConfigAction: String, CaseIterable {
    case toggleSidebar = "toggle_sidebar"
    case toggleBrowser = "toggle_browser"
}

/// Muxify's keybinds: each action's triggers, in the order they were listed.
/// No trigger belongs to two actions.
struct Keybinds: Equatable {
    let triggers: [ConfigAction: [KeyTrigger]]

    /// The defaults as the user spells them, so the template can show them.
    static let defaultSpelling: KeyValuePairs<ConfigAction, [String]> = [
        .toggleSidebar: ["cmd+s", "ctrl+cmd+s"],
        .toggleBrowser: ["cmd+b"],
    ]

    static let defaults = Keybinds(triggers: Dictionary(uniqueKeysWithValues: defaultSpelling.map { action, spellings in
        (action, spellings.map { try! KeyTrigger($0) })
    }))

    func action(for trigger: KeyTrigger) -> ConfigAction? {
        triggers.first { $0.value.contains(trigger) }?.key
    }

    /// The trigger menus and tooltips show for `action`.
    func firstTrigger(for action: ConfigAction) -> KeyTrigger? {
        triggers[action]?.first
    }
}
