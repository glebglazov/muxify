import SwiftUI

/// Where an item dragged in a list lands: before or after another item of the list.
enum DropPlacement<ID: Hashable>: Equatable {
    case before(ID)
    case after(ID)

    var anchor: ID {
        switch self {
        case .before(let id), .after(let id): return id
        }
    }

    /// Where an item dragged to `y` lands: before the first item that does not end above `y` when `y` is in its
    /// upper half, after it otherwise, and after the last item below them all. `frames` are the items the list
    /// shows, in the coordinate space of `y`. Nil when the item under `y` is the dragged one.
    static func at(_ y: CGFloat, frames: [ID: CGRect], dragging id: ID) -> DropPlacement? {
        let items = frames.sorted { $0.value.minY < $1.value.minY }
        guard let (anchor, frame) = items.first(where: { y < $0.value.maxY }) ?? items.last, anchor != id else { return nil }
        return y < frame.midY ? .before(anchor) : .after(anchor)
    }
}

/// A long press that lifts an item of a list and drags it to a new place. Nothing shows for the first 0.2 s, so a
/// click stays a click; until 0.5 s the item shrinks a little; then it lifts and follows the pointer, with a drop
/// line at its placement. A list holds one value for all its items, since only one item moves at a time.
enum LongPressDrag<ID: Hashable>: Equatable {
    case idle
    case pressing(ID)
    case shrinking(ID)
    case lifted(ID, translation: CGFloat, placement: DropPlacement<ID>?)

    static var shrinkDelay: Duration { .milliseconds(200) }
    static var liftDelay: Duration { .milliseconds(500) }

    func isShrinking(_ id: ID) -> Bool { self == .shrinking(id) }

    /// How far the lifted item follows the pointer, nil when `id` is not lifted.
    func translation(of id: ID) -> CGFloat? {
        if case .lifted(id, let translation, _) = self { return translation }
        return nil
    }

    /// The placement a drop line shows at `id`, which is the anchor of the lifted item's placement.
    func dropLine(at id: ID) -> DropPlacement<ID>? {
        if case .lifted(_, _, let placement?) = self, placement.anchor == id { return placement }
        return nil
    }
}

private struct LongPressDragModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @Binding var state: LongPressDrag<ID>
    let coordinateSpace: String
    let isEnabled: Bool
    let placement: (CGFloat) -> DropPlacement<ID>?
    let onTap: () -> Void
    let onDrop: (DropPlacement<ID>) -> Void

    @State private var timer: Task<Void, Never>?
    /// The pointer moved before the item lifted: the press is neither a click nor a drag.
    @State private var cancelled = false

    /// Movement the pointer may make before the item lifts and still count as a held press.
    private static var slop: CGFloat { 4 }

    func body(content: Content) -> some View {
        content.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
            .onChanged(changed)
            .onEnded(ended))
    }

    private func changed(_ value: DragGesture.Value) {
        guard !cancelled else { return }
        switch state {
        case .lifted(id, _, _):
            state = .lifted(id, translation: value.translation.height, placement: placement(value.location.y))
        case .pressing(id), .shrinking(id):
            if hypot(value.translation.width, value.translation.height) > Self.slop { cancel() }
        default:
            state = .pressing(id)
            guard isEnabled else { return }
            timer = Task { @MainActor in
                try? await Task.sleep(for: LongPressDrag<ID>.shrinkDelay)
                guard !Task.isCancelled, state == .pressing(id) else { return }
                withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.3)) { state = .shrinking(id) }
                try? await Task.sleep(for: LongPressDrag<ID>.liftDelay - LongPressDrag<ID>.shrinkDelay)
                guard !Task.isCancelled, state == .shrinking(id) else { return }
                withAnimation(.spring(duration: 0.2)) { state = .lifted(id, translation: 0, placement: nil) }
            }
        }
    }

    private func ended(_ value: DragGesture.Value) {
        timer?.cancel()
        let ending = state
        let wasCancelled = cancelled
        cancelled = false
        withAnimation(.spring(duration: 0.25)) { state = .idle }
        guard !wasCancelled else { return }
        switch ending {
        case .lifted(id, _, let placement?): onDrop(placement)
        case .pressing(id), .shrinking(id): onTap()
        default: break
        }
    }

    private func cancel() {
        timer?.cancel()
        cancelled = true
        withAnimation(.spring(duration: 0.25)) { state = .idle }
    }
}

extension View {
    /// Makes the view the handle of a `LongPressDrag` item: a click calls `onTap`, a long press lifts the item, and
    /// letting go of a lifted item calls `onDrop` with its placement. `placement` maps the pointer's height in
    /// `coordinateSpace` to a placement. While disabled, a long press does nothing and a click still works.
    func longPressDrag<ID: Hashable>(_ id: ID, state: Binding<LongPressDrag<ID>>, in coordinateSpace: String, isEnabled: Bool = true,
                                     placement: @escaping (CGFloat) -> DropPlacement<ID>?, onTap: @escaping () -> Void,
                                     onDrop: @escaping (DropPlacement<ID>) -> Void) -> some View {
        modifier(LongPressDragModifier(id: id, state: state, coordinateSpace: coordinateSpace, isEnabled: isEnabled,
                                       placement: placement, onTap: onTap, onDrop: onDrop))
    }

    /// How an item of a `LongPressDrag` list looks in each phase: shrunk while pressed, raised and following the
    /// pointer when lifted, with a drop line before or after it when the lifted item would land there.
    func longPressDragLook<ID: Hashable>(_ id: ID, state: LongPressDrag<ID>, lineOffset: CGFloat) -> some View {
        let translation = state.translation(of: id)
        let line = state.dropLine(at: id)
        let isBefore: Bool = if case .before = line { true } else { false }
        return scaleEffect(translation != nil ? 1.025 : state.isShrinking(id) ? 0.982 : 1, anchor: UnitPoint(x: 0.5, y: 0.3))
            .shadow(color: .black.opacity(translation != nil ? 0.5 : 0), radius: translation != nil ? 17 : 0, y: translation != nil ? 14 : 0)
            .offset(y: translation ?? 0)
            .zIndex(translation != nil ? 30 : 0)
            .overlay(alignment: isBefore ? .top : .bottom) {
                if line != nil {
                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(height: 2)
                        .padding(.horizontal, 4)
                        .offset(y: isBefore ? -lineOffset : lineOffset)
                        .allowsHitTesting(false)
                }
            }
    }
}
