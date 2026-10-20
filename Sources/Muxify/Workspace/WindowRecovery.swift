import MuxifyCore
/// Selection history belongs to one App Window, not tmux's server-wide last
/// Window option. A closed Window falls back to the Window before it in its
/// Session, else the one after it. With the whole Session gone, it falls back
/// to the previously selected Window, then Sidebar order.
struct WindowRecovery {
    private(set) var currentWindowID: String?
    private(set) var previousWindowID: String?

    mutating func selected(_ windowID: String?) {
        guard let windowID, windowID != currentWindowID else { return }
        previousWindowID = currentWindowID
        currentWindowID = windowID
    }

    /// `listedBefore` is the inventory that still had the closed Window.
    func fallback(in windows: [TmuxWindow], listedBefore: [TmuxWindow]) -> TmuxWindow? {
        if let closed = listedBefore.first(where: { $0.id == currentWindowID }) {
            let siblings = listedBefore.filter { $0.sessionID == closed.sessionID }.map(\.id)
            if let index = siblings.firstIndex(of: closed.id) {
                for id in siblings[..<index].reversed() + siblings[(index + 1)...] {
                    if let window = windows.first(where: { $0.id == id }) { return window }
                }
            }
        }
        return windows.first { $0.id == previousWindowID } ?? windows.first
    }

    func selectionDisappeared(in windows: [TmuxWindow]) -> Bool {
        guard let currentWindowID else { return false }
        return !windows.contains { $0.id == currentWindowID }
    }
}
