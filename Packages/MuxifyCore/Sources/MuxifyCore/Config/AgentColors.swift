import Foundation

/// A macOS system color that `ui.agent_colors` can name. Each one adapts to light and dark appearance.
public enum SystemColorName: String, CaseIterable, Sendable {
    case blue, orange, red, green, yellow, purple, pink, teal, gray
}

/// The color of one kind of Agent mark.
public enum AgentColor: Equatable, Sendable {
    case system(SystemColorName)
    /// The same in light and dark appearance.
    case rgb(red: UInt8, green: UInt8, blue: UInt8)

    /// A system color name or `#RRGGBB`, in any case.
    public init?(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let name = SystemColorName(rawValue: value) {
            self = .system(name)
            return
        }
        let digits = value.dropFirst()
        guard value.hasPrefix("#"), digits.count == 6, digits.allSatisfy(\.isHexDigit),
              let packed = UInt32(digits, radix: 16) else { return nil }
        self = .rgb(red: UInt8(packed >> 16 & 0xff), green: UInt8(packed >> 8 & 0xff), blue: UInt8(packed & 0xff))
    }
}

/// `ui.agent_colors`: the color of each kind of Agent mark, on every surface.
public struct AgentColors: Equatable, Sendable {
    public var working = AgentColor.system(.gray)
    public var done = AgentColor.system(.blue)
    public var failed = AgentColor.system(.red)
    public var blocked = AgentColor.system(.orange)

    public init() {}

    public subscript(mark: AgentMark) -> AgentColor {
        get {
            switch mark {
            case .working: working
            case .done: done
            case .failed: failed
            case .blocked: blocked
            }
        }
        set {
            switch mark {
            case .working: working = newValue
            case .done: done = newValue
            case .failed: failed = newValue
            case .blocked: blocked = newValue
            }
        }
    }
}
