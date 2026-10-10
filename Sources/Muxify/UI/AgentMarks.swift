import SwiftUI
import MuxifyCore

/// An Agent's Status dot. A working Agent's dot breathes, so movement always means busy.
struct StatusDot: View {
    let color: Color
    let breathes: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .breathing(breathes)
    }
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .working: return .blue
        case .blocked: return .orange
        case .failed: return .red
        case .done: return .green
        }
    }

    /// The Status a card or palette row shows for its Agents: the most urgent Notification, else working.
    static func shown(mark: AgentStatus?, working: Bool) -> AgentStatus? {
        mark ?? (working ? .working : nil)
    }
}

/// Fades the view in and out on the clock every working mark reads, so they breathe together. It only fades, never
/// moves, and stays still with Reduce Motion or `ui.pulse: false`.
private struct Breathing: ViewModifier {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulses) private var pulses

    private static let period: TimeInterval = 1.6

    func body(content: Content) -> some View {
        if isOn, pulses, !reduceMotion {
            // 30 fps is plenty for a slow fade, and Agents can work for hours.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                content.opacity(0.675 + 0.325 * cos(2 * .pi * context.date.timeIntervalSinceReferenceDate / Self.period))
            }
        } else {
            content
        }
    }
}

extension View {
    func breathing(_ isOn: Bool) -> some View { modifier(Breathing(isOn: isOn)) }
}

private struct PulsesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `ui.pulse` in the Config.
    var pulses: Bool {
        get { self[PulsesKey.self] }
        set { self[PulsesKey.self] = newValue }
    }
}
