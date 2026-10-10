import MuxifyCore
/// Selection history belongs to one App Window, not tmux's server-wide last
/// Window option. A closed previous Window falls back to Sidebar order.
struct WindowRecovery {
    private(set) var currentWindowID: String?
    private(set) var previousWindowID: String?

    mutating func selected(_ windowID: String?) {
        guard let windowID, windowID != currentWindowID else { return }
        previousWindowID = currentWindowID
        currentWindowID = windowID
    }

    func fallback(in windows: [TmuxWindow]) -> TmuxWindow? {
        windows.first { $0.id == previousWindowID } ?? windows.first
    }

    func selectionDisappeared(in windows: [TmuxWindow]) -> Bool {
        guard let currentWindowID else { return false }
        return !windows.contains { $0.id == currentWindowID }
    }
}
