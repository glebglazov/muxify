import AppKit
import Carbon.HIToolbox
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

    // Printable keys are matched by the character they type with only ⌘ held
    // on the current layout, not by their position, so a trigger follows the
    // layout the same way the menu's shortcuts do, and on a non-Latin layout
    // such as Russian `cmd+p` is still the key labelled P. Keys that type no
    // character are matched by position.
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
    init?(_ event: NSEvent, layout: KeyboardLayout? = .current) {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.modifiers = modifiers
        if let special = SpecialKey.allCases.first(where: { $0.keyCodes.contains(event.keyCode) }) {
            key = .special(special)
        } else if let character = layout?.commandCharacter(keyCode: event.keyCode) {
            key = .character(character)
        } else {
            return nil
        }
    }

    var shortcut: KeyboardShortcut {
        var eventModifiers: SwiftUI.EventModifiers = []
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

/// The characters a keyboard layout types, read from its key table.
struct KeyboardLayout {
    private let table: Data

    /// The layout the user types with now. An input method such as Japanese
    /// resolves to the key layout under it.
    static var current: KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return KeyboardLayout(source)
    }

    /// The installed layout with this id, such as `com.apple.keylayout.Russian`.
    init?(inputSourceID: String) {
        let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else { return nil }
        self.init(source)
    }

    private init?(_ source: TISInputSource) {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        table = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    }

    /// The character the key types with only ⌘ held, lowercased. Shift is
    /// left off so `cmd+shift+1` stays "1" and not "!"; Control is left off
    /// because with it the key types no character.
    func commandCharacter(keyCode: UInt16) -> Character? {
        var deadKeys: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        let status = table.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8) & 0xFF,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, units.count, &length, &units)
        }
        guard status == noErr else { return nil }
        return String(utf16CodeUnits: units, count: length).lowercased().first
    }
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
