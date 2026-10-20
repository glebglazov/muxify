import Foundation

/// A Snooze of a set of Topics until one time. The time replaces each Topic's earlier time, also a later one,
/// because the user chose each Topic. Zen, which does not ask about each Topic, never makes a Snooze shorter.
public struct SnoozeSet: Equatable {
    /// The open Topics of the set with the new time, in the order of the set.
    public let saves: [TopicRecord]
    /// The Topics of `saves` that were Snoozed until later.
    public let shortened: [String]

    public init(_ ids: [String], until: SnoozeDeadline, records: [TopicRecord]) {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var saves: [TopicRecord] = []
        var shortened: [String] = []
        for id in ids {
            guard var record = byID[id], record.settledAt == nil else { continue }
            if Self.shortens(record.snoozeDeadline, to: until) { shortened.append(id) }
            record.snoozedUntil = until.stored
            saves.append(record)
        }
        self.saves = saves
        self.shortened = shortened
    }

    private static func shortens(_ current: SnoozeDeadline?, to until: SnoozeDeadline) -> Bool {
        switch (current, until) {
        case (.never?, .at): return true
        case (.at(let date)?, .at(let end)): return date > end
        default: return false
        }
    }
}
