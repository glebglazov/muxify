import AppKit
import SwiftUI

/// A row's hover label: after the pointer rests on the row, a label opens over it with the row's full title, when the
/// row cuts it off, and a small second line with more about the row. One label shows at a time, in a borderless panel
/// that can reach past the Sidebar's edge. It never takes Focus or a click.
@MainActor
final class HoverLabels {
    static let shared = HoverLabels()

    /// How long the pointer rests on a row before its label opens.
    private static let delay: TimeInterval = 0.4
    /// After a label closes, the next row's label opens at once for this long, so moving down a list reads row by row.
    private static let coolDown: TimeInterval = 0.3

    private let panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.setAccessibilityIdentifier("hover-label")
        return panel
    }()
    private var owner: HoverAnchor?
    private var pending: DispatchWorkItem?
    private var closedAt = Date.distantPast

    func enter(_ anchor: HoverAnchor, title: String, titleFont: NSFont, detail: String, onlyWhenCutOff: Bool) {
        owner = anchor
        pending?.cancel()
        let show = { [weak self, weak anchor] in
            guard let self, let anchor, self.owner === anchor else { return }
            self.show(anchor, title: title, titleFont: titleFont, detail: detail, onlyWhenCutOff: onlyWhenCutOff)
        }
        if panel.isVisible || Date().timeIntervalSince(closedAt) < Self.coolDown {
            show()
        } else {
            let work = DispatchWorkItem(block: show)
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
        }
    }

    func leave(_ anchor: HoverAnchor) {
        guard owner === anchor else { return }
        owner = nil
        pending?.cancel()
        guard panel.isVisible else { return }
        closedAt = Date()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func show(_ anchor: HoverAnchor, title: String, titleFont: NSFont, detail: String, onlyWhenCutOff: Bool) {
        guard let view = anchor.view, let window = view.window else { return }
        let titleFrame = window.convertToScreen(view.convert(view.bounds, to: nil))
        let width = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let cutOff = width > titleFrame.width + 0.5
        guard cutOff || (!onlyWhenCutOff && !detail.isEmpty) else { return }
        let content = NSHostingView(rootView: HoverLabelView(title: cutOff ? title : nil, titleFont: titleFont, detail: detail))
        let size = content.fittingSize
        panel.contentView = content
        // The label's title sits on the row's title, so the row seems to open up in place.
        let origin = NSPoint(x: titleFrame.minX - HoverLabelView.padding.leading,
                             y: titleFrame.maxY + HoverLabelView.padding.top - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || panel.isVisible {
            panel.alphaValue = 1
            panel.orderFront(nil)
        } else {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }
}

private struct HoverLabelView: View {
    static let padding = EdgeInsets(top: 4, leading: 7, bottom: 5, trailing: 8)

    let title: String?
    let titleFont: NSFont
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title { Text(title).font(Font(titleFont)) }
            if !detail.isEmpty { Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary) }
        }
        .fixedSize()
        .padding(Self.padding)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// Where a row's title is on screen, for its hover label.
@MainActor
final class HoverAnchor {
    fileprivate weak var view: NSView?
}

private struct HoverAnchorView: NSViewRepresentable {
    let anchor: HoverAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

private struct HoverAnchorKey: EnvironmentKey {
    static let defaultValue: HoverAnchor? = nil
}

extension EnvironmentValues {
    fileprivate var hoverAnchor: HoverAnchor? {
        get { self[HoverAnchorKey.self] }
        set { self[HoverAnchorKey.self] = newValue }
    }
}

private struct HoverLabelModifier: ViewModifier {
    let title: String
    let titleFont: NSFont
    let detail: String
    let onlyWhenCutOff: Bool

    @State private var anchor = HoverAnchor()

    func body(content: Content) -> some View {
        content
            .environment(\.hoverAnchor, anchor)
            .onHover { inside in
                if inside { HoverLabels.shared.enter(anchor, title: title, titleFont: titleFont, detail: detail, onlyWhenCutOff: onlyWhenCutOff) }
                else { HoverLabels.shared.leave(anchor) }
            }
            .onDisappear { HoverLabels.shared.leave(anchor) }
    }
}

private struct HoverTitleModifier: ViewModifier {
    @Environment(\.hoverAnchor) private var anchor

    func body(content: Content) -> some View {
        content.background { if let anchor { HoverAnchorView(anchor: anchor).accessibilityHidden(true) } }
    }
}

extension View {
    /// Gives the row a hover label with its full `title`, drawn in `titleFont`, and `detail` under it. With
    /// `onlyWhenCutOff`, for a row that already shows its detail, the label opens only when the title is cut off.
    /// Mark the row's title view with `hoverLabelTitle()`.
    func hoverLabel(title: String, titleFont: NSFont, detail: String, onlyWhenCutOff: Bool = false) -> some View {
        modifier(HoverLabelModifier(title: title, titleFont: titleFont, detail: detail, onlyWhenCutOff: onlyWhenCutOff))
    }

    /// The title of a row with a `hoverLabel`: the label aligns with it, and shows the full title when it is cut off.
    func hoverLabelTitle() -> some View { modifier(HoverTitleModifier()) }
}
