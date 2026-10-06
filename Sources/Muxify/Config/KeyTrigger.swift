import AppKit
import SwiftUI

/// A key with its modifiers, written as in Ghostty: `ctrl+cmd+s`,
/// `cmd+shift+left_bracket`.
struct KeyTrigger: Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    // Printable keys are matched by the character they type with no
    // modifiers on the current layout, not by their position, so a trigger
    // follows the layout the same way the menu's shortcuts do. Keys that
    // type no character are matched by position.
    enum Key: Hashable {
        case character(Character)
        case special(SpecialKey)
    }

    enum SpecialKey: String, CaseIterable {
        case enter, tab, escape, backspace, left, right, up, down
    }

    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    let modifiers: Modifiers
    let key: Key

    init(modifiers: Modifiers, key: Key) {
        self.modifiers = modifiers
        self.key = key
    }

    init(_ string: String) throws {
        var parts = string.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = parts.popLast(), !keyName.isEmpty else {
            throw ParseError(description: "bad trigger \"\(string)\": no key")
        }
        var modifiers: Modifiers = []
        for name in parts {
            guard let modifier = Self.modifierNames[name] else {
                throw ParseError(description: "bad trigger \"\(string)\": unknown modifier \"\(name)\"")
            }
            modifiers.insert(modifier)
        }
        if let special = SpecialKey(rawValue: keyName) {
            key = .special(special)
        } else if let character = Self.keyNames[keyName] ?? (keyName.count == 1 ? keyName.first : nil) {
            key = .character(character)
        } else {
            throw ParseError(description: "bad trigger \"\(string)\": unknown key \"\(keyName)\"")
        }
        self.modifiers = modifiers
    }

    /// The trigger a key press stands for, or nil for a key Muxify cannot
    /// name.
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.modifiers = modifiers
        if let special = SpecialKey.allCases.first(where: { $0.keyCodes.contains(event.keyCode) }) {
            key = .special(special)
        } else if let character = event.characters(byApplyingModifiers: [])?.lowercased().first {
            key = .character(character)
        } else {
            return nil
        }
    }

    var shortcut: KeyboardShortcut {
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        switch key {
        case .character(let character): return KeyboardShortcut(KeyEquivalent(character), modifiers: eventModifiers)
        case .special(let special): return KeyboardShortcut(special.keyEquivalent, modifiers: eventModifiers)
        }
    }

    /// As macOS writes shortcuts in menus, e.g. `⌃⌘S`.
    var symbol: String {
        let glyphs: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = glyphs.filter { modifiers.contains($0.0) }.map(\.1).joined()
        switch key {
        case .character(" "): return prefix + "Space"
        case .character(let character): return prefix + character.uppercased()
        case .special(let special): return prefix + special.glyph
        }
    }

    private static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "super": .command,
        "ctrl": .control, "control": .control,
        "alt": .option, "opt": .option, "option": .option,
        "shift": .shift,
    ]

    /// Ghostty's names for keys that type a character.
    private static let keyNames: [String: Character] = {
        var names: [String: Character] = [
            "comma": ",", "period": ".", "slash": "/", "semicolon": ";", "quote": "'",
            "backquote": "`", "minus": "-", "equal": "=", "left_bracket": "[",
            "right_bracket": "]", "backslash": "\\", "space": " ",
        ]
        for digit in "0123456789" { names["digit_\(digit)"] = digit }
        for letter in "abcdefghijklmnopqrstuvwxyz" { names["key_\(letter)"] = letter }
        return names
    }()
}

private extension KeyTrigger.SpecialKey {
    var keyCodes: [UInt16] {
        switch self {
        case .enter: [0x24, 0x4C]
        case .tab: [0x30]
        case .escape: [0x35]
        case .backspace: [0x33]
        case .left: [0x7B]
        case .right: [0x7C]
        case .down: [0x7D]
        case .up: [0x7E]
        }
    }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .enter: .return
        case .tab: .tab
        case .escape: .escape
        case .backspace: .delete
        case .left: .leftArrow
        case .right: .rightArrow
        case .down: .downArrow
        case .up: .upArrow
        }
    }

    var glyph: String {
        switch self {
        case .enter: "↩"
        case .tab: "⇥"
        case .escape: "⎋"
        case .backspace: "⌫"
        case .left: "←"
        case .right: "→"
        case .down: "↓"
        case .up: "↑"
        }
    }
}
