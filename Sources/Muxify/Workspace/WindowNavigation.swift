/// A Window's position in its Session, independent of tmux's window indices.
enum WindowNavigation {
    case position(Int)
    case last

    /// An index into the Session's Windows in sidebar order. Missing positions do nothing.
    func targetIndex(currentIndex: Int, count: Int) -> Int? {
        guard currentIndex >= 0, currentIndex < count else { return nil }
        switch self {
        case .position(let position):
            guard position >= 1, position <= count else { return nil }
            return position - 1
        case .last:
            return count - 1
        }
    }
}
