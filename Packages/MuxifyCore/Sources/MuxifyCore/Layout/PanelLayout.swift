/// What a Window shows of its Terminal and Browser. The toggles say which
/// sides are shown and never hide both. Focus shows one side alone, with the
/// Sidebar hidden, without changing the toggles; when it ends, the toggles
/// show again.
public struct PanelLayout: Hashable {
    public enum Side: Hashable {
        case terminal, browser

        public var other: Side { self == .terminal ? .browser : .terminal }
    }

    /// The sides the toggles show.
    public enum Shown: Hashable {
        case terminal, both, browser

        init(alone side: Side) {
            self = side == .terminal ? .terminal : .browser
        }

        func includes(_ side: Side) -> Bool {
            self == .both || self == Shown(alone: side)
        }
    }

    public private(set) var shown: Shown
    public private(set) var focus: Side?

    public init(shown: Shown = .terminal, focus: Side? = nil) {
        self.shown = shown
        self.focus = focus
    }

    /// Whether `side` is on screen: the toggles, filtered by Focus.
    public func shows(_ side: Side) -> Bool {
        if let focus { return side == focus }
        return shown.includes(side)
    }

    public var hidesSidebar: Bool { focus != nil }

    /// The only side on screen can't be hidden.
    public func canToggle(_ side: Side) -> Bool {
        !shows(side) || shows(side.other)
    }

    /// Shows or hides `side`. During Focus, what is on screen becomes the
    /// toggles first, so the toggle changes what the user sees.
    public mutating func toggle(_ side: Side) {
        guard canToggle(side) else { return }
        commitFocus()
        shown = shown.includes(side) ? Shown(alone: side.other) : .both
    }

    public mutating func show(_ side: Side) {
        if !shows(side) { toggle(side) }
    }

    /// Focus on `side` changes something: it hides the Sidebar or the other
    /// side, or it moves or ends Focus.
    public func canFocus(_ side: Side, sidebarShown: Bool) -> Bool {
        focus != nil || sidebarShown || !shows(side) || shows(side.other)
    }

    /// Focuses `side`, or ends Focus when `side` is in Focus already.
    public mutating func toggleFocus(_ side: Side, sidebarShown: Bool) {
        guard canFocus(side, sidebarShown: sidebarShown) else { return }
        focus = focus == side ? nil : side
    }

    public mutating func endFocus() {
        focus = nil
    }

    /// Ends Focus and keeps what it shows: the side in Focus, alone.
    public mutating func commitFocus() {
        guard let focus else { return }
        shown = Shown(alone: focus)
        self.focus = nil
    }

    /// The Browser has no Tab left, so only the Terminal can show.
    public mutating func closeBrowser() {
        shown = .terminal
        if focus == .browser { focus = nil }
    }
}
