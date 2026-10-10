import AppKit

/// Sidebar text keeps its existing hierarchy around a configurable base size.
/// Symbols, logos and status dots deliberately do not use this typography.
public struct SidebarTypography: Equatable {
    public var fontSize: Double = 12
    public var fontFamily: String = "system"

    public init(fontSize: Double = 12, fontFamily: String = "system") {
        self.fontSize = fontSize
        self.fontFamily = fontFamily
    }

    public static var fontFamilies: [String] { NSFontManager.shared.availableFontFamilies }

    /// Preserve native system-font selection instead of naming a particular
    /// system face. The catalogue is injectable without requiring test fonts.
    public static func canonicalFamily(_ name: String,
                                       families: () -> [String] = { Self.fontFamilies }) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        if name.caseInsensitiveCompare("system") == .orderedSame { return "system" }
        return families().first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
