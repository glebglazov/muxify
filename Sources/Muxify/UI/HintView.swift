import SwiftUI
import MuxifyCore

private struct HintAnchors: PreferenceKey {
    static var defaultValue: [QuickSwitchTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [QuickSwitchTarget: Anchor<CGRect>], nextValue: () -> [QuickSwitchTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct HintBadge: View {
    let target: QuickSwitchTarget
    let triggers: [KeyTrigger]

    var body: some View {
        Text(triggers.map(\.symbol).joined(separator: " "))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(red: 30 / 255, green: 31 / 255, blue: 35 / 255).opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.35), lineWidth: 1) }
            .environment(\.colorScheme, .dark)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityIdentifier(target.accessibilityID)
    }
}

struct HintKey: View {
    let target: QuickSwitchTarget
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityIdentifier(target.accessibilityID)
    }
}

/// The place of a card's Hint: just after its title, on the title's first baseline.
/// `cardHints` draws the Hint over this place, because the header hides its children from accessibility, and the card's
/// dimming must not dim the badge. The place is as wide as the key, so the title does not wrap again when the badge shows.
struct CardHintSlot: View {
    let target: QuickSwitchTarget
    @Environment(\.quickSwitchHints) private var hints

    var body: some View {
        if hints.restKey(for: target) != nil || !hints[target].isEmpty {
            CardRestKey(target: target, key: hints.restKey(for: target) ?? "")
                .hidden()
                .hintAnchor(target)
        }
    }
}

/// A card's key at rest, on a faint circle of the theme's text colour, so it does not read as one of the counts in the
/// card and does not draw the eye more than the title.
struct CardRestKey: View {
    let target: QuickSwitchTarget
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.7))
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Color.primary.opacity(0.12)))
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityIdentifier(target.accessibilityID)
    }
}

extension View {
    func hintAnchor(_ target: QuickSwitchTarget?) -> some View {
        anchorPreference(key: HintAnchors.self, value: .bounds) { anchor in
            target.map { [$0: anchor] } ?? [:]
        }
    }

    func cardHints(_ hints: HintPresentation) -> some View {
        overlayPreferenceValue(HintAnchors.self) { anchors in
            GeometryReader { proxy in
                ForEach(anchors.keys.sorted { $0.accessibilityID < $1.accessibilityID }, id: \.self) { target in
                    if let anchor = anchors[target] {
                        let rect = proxy[anchor]
                        if case .window = target {
                            Group {
                                if !hints[target].isEmpty {
                                    HintBadge(target: target, triggers: hints[target])
                                } else if let key = hints.restKey(for: target) {
                                    HintKey(target: target, key: key)
                                }
                            }
                            .frame(width: 13, height: rect.height, alignment: .topLeading)
                            .offset(x: rect.minX + 5, y: rect.minY + 5)
                        } else {
                            // The badge ends where the key ends, and grows over the title.
                            Color.clear
                                .frame(width: rect.width, height: rect.height)
                                .overlay(alignment: .trailing) {
                                    if !hints[target].isEmpty {
                                        HintBadge(target: target, triggers: hints[target])
                                    } else if let key = hints.restKey(for: target) {
                                        CardRestKey(target: target, key: key)
                                    }
                                }
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .transformPreference(HintAnchors.self) { $0 = [:] }
    }

    func quickSwitchHint(_ target: QuickSwitchTarget, hints: HintPresentation) -> some View {
        overlay(alignment: .topTrailing) {
            if !hints[target].isEmpty {
                HintBadge(target: target, triggers: hints[target]).padding(4)
            }
        }
    }
}
