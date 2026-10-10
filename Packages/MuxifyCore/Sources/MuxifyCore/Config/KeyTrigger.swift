import Foundation

/// A key with its modifiers, written as in Ghostty: `ctrl+cmd+s`,
/// `cmd+shift+left_bracket`.
public struct KeyTrigger: Hashable {
    public struct Modifiers: OptionSet, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    // Printable keys are matched by the character they type with only ⌘ held
    // on the current layout, not by their position, so a trigger follows the
    // layout the same way the menu's shortcuts do, and on a non-Latin layout
    // such as Russian `cmd+p` is still the key labelled P. Keys that type no
    // character are matched by position.
    public enum Key: Hashable {
        case character(Character)
        case special(SpecialKey)
    }

    public enum SpecialKey: String, CaseIterable {
        case enter, tab, escape, backspace, left, right, up, down
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    public let modifiers: Modifiers
    public let key: Key

    public init(modifiers: Modifiers, key: Key) {
        self.modifiers = modifiers
        self.key = key
    }

    public init(_ string: String) throws {
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
