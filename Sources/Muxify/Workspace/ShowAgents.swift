import Foundation
import MuxifyCore

/// The View menu's Show Agents choice, kept for each Sidebar mode in UserDefaults.
/// A mode the user has not toggled yet takes the single value earlier builds stored for both modes.
struct ShowAgents {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    subscript(mode: SidebarMode) -> Bool {
        get {
            defaults.object(forKey: Self.key(mode)) as? Bool
                ?? defaults.object(forKey: "agentsVisible") as? Bool
                ?? true
        }
        set { defaults.set(newValue, forKey: Self.key(mode)) }
    }

    private static func key(_ mode: SidebarMode) -> String {
        "agentsVisible" + mode.rawValue
    }
}
