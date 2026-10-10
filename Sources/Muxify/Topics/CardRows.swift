import Foundation

/// The rows an open Sidebar card lists before "N more…".
enum CardRows {
    static let limit = 5

    /// How many of a card's rows it lists: the first `limit`, or all of them once the user asked, or when the
    /// selected Window's rows reach past the limit, so a card never hides where the user is.
    static func shownCount(_ items: [TopicsModel.SessionChildren.Item], selectedWindowID: String?, showsAll: Bool) -> Int {
        let selectionHidden = items.lastIndex { $0.window.id == selectedWindowID }.map { $0 >= limit } ?? false
        return showsAll || selectionHidden ? items.count : min(items.count, limit)
    }
}
