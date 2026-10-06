import AppKit
import SwiftUI

/// The strip you drag to move a divider between panels, a few points wider
/// than the line it sits on.
///
/// The strip lies over the terminal and the Browser, AppKit views that set
/// their own cursor as the mouse moves (Ghostty an I-beam, WebKit the page's
/// cursor) whatever SwiftUI draws over them. So the divider sees the window's
/// mouse events before they are dispatched and keeps the ones in its strip;
/// the views underneath never hear about them.
struct PanelDivider: NSViewRepresentable {
    /// The pointer's horizontal travel since the drag began.
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> PanelDividerView { PanelDividerView() }

    func updateNSView(_ view: PanelDividerView, context: Context) {
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
    }
}

final class PanelDividerView: NSView {
    /// How far the strip reaches past the line on each side.
    static let reach: CGFloat = 4

    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private var monitor: Any?
    private var trackingArea: NSTrackingArea?
    /// Where the drag began, in window coordinates; nil when not dragging.
    private var dragOriginX: CGFloat?
    /// The cursor from before the pointer entered the strip; nil while outside.
    private var cursorBeforeHover: NSCursor?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    // The monitor takes the strip's clicks and moves; whatever it lets
    // through (scrolling, right clicks) belongs to the view underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .cursorUpdate, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        } else if window == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            dragOriginX = nil
            setHovering(false)
        }
    }

    override func updateTrackingAreas() {
        // Makes AppKit report moves across the whole strip, even over SwiftUI
        // content that doesn't ask for them, and tells us when the pointer
        // leaves it, even out of the window.
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseExited(with event: NSEvent) {
        if dragOriginX == nil { setHovering(false) }
    }

    /// Returns nil for the events the divider keeps.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        let point = event.locationInWindow
        let inStrip = convert(bounds, to: nil).contains(point)
        switch event.type {
        case .leftMouseDown:
            guard inStrip else { return event }
            dragOriginX = point.x
            setHovering(true)
        case .leftMouseDragged:
            guard let dragOriginX else { return event }
            NSCursor.resizeLeftRight.set()
            onDrag(point.x - dragOriginX)
        case .leftMouseUp:
            guard dragOriginX != nil else { return event }
            dragOriginX = nil
            onDragEnded()
            setHovering(inStrip)
        default:
            if dragOriginX != nil {
                NSCursor.resizeLeftRight.set()
                return nil
            }
            setHovering(inStrip)
            return inStrip ? nil : event
        }
        return nil
    }

    private func setHovering(_ hovering: Bool) {
        if hovering {
            if cursorBeforeHover == nil {
                cursorBeforeHover = NSCursor.current
                // WebKit may still be answering a move from before the pointer
                // got here and set the page's cursor; take it back once it has.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    if self?.cursorBeforeHover != nil { NSCursor.resizeLeftRight.set() }
                }
            }
            NSCursor.resizeLeftRight.set()
        } else if let cursor = cursorBeforeHover {
            cursorBeforeHover = nil
            cursor.set()
        }
    }
}
