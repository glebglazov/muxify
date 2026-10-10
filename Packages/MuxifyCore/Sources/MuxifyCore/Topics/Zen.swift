import Foundation

/// A Zen that is on: `$XDG_STATE_HOME/muxify/zen.json`, beside the Topic records.
/// It lists only the Topics that Zen changed, so End Zen puts back exactly those.
public struct ZenRecord: Codable, Equatable, Sendable {
    public struct Change: Codable, Equatable, Sendable {
        public let topicID: String
        /// The Topic's `snoozed_until` before Zen.
        public let previous: String?

        private enum CodingKeys: String, CodingKey {
            case topicID = "topic_id", previous = "previous_snoozed_until"
        }
    }

    /// Zen always keeps a Topic. No Topic is not a Topic, so a record without one does not decode.
    public let keptTopicID: String
    /// The stored Snooze time Zen gave each changed Topic.
    public let until: String
    public var changes: [Change]

    public var deadline: SnoozeDeadline? { SnoozeDeadline(stored: until) }

    private enum CodingKeys: String, CodingKey {
        case keptTopicID = "kept_topic_id", until, changes
    }

    /// Snoozes every open Topic but the kept one until `until`. Zen never makes a Snooze shorter, so a Topic
    /// Snoozed until Unsnooze, or past `until`, keeps its Snooze and is not in the record.
    public static func start(keeping kept: String, until: SnoozeDeadline, records: [TopicRecord]) -> (zen: ZenRecord, saves: [TopicRecord]) {
        var changes: [Change] = []
        var saves: [TopicRecord] = []
        for var record in records where record.settledAt == nil && record.id != kept && lengthens(record.snoozeDeadline, to: until) {
            changes.append(Change(topicID: record.id, previous: record.snoozedUntil))
            record.snoozedUntil = until.stored
            saves.append(record)
        }
        return (ZenRecord(keptTopicID: kept, until: until.stored, changes: changes), saves)
    }

    /// A due Snooze is earlier than any Zen, since a Zen time is in the future.
    private static func lengthens(_ current: SnoozeDeadline?, to until: SnoozeDeadline) -> Bool {
        switch (current, until) {
        case (nil, _), (.at?, .never): return true
        case (.never?, _): return false
        case (.at(let date)?, .at(let end)): return date < end
        }
    }

    /// End Zen: each changed Topic gets back its earlier Snooze, or none when that time is past. A Topic
    /// that was Settled, or whose Snooze the user changed during Zen, is left as it is.
    public func end(records: [TopicRecord], now: Date) -> [TopicRecord] {
        changes.compactMap { change in
            guard var record = records.first(where: { $0.id == change.topicID && $0.settledAt == nil }),
                  record.snoozedUntil == until else { return nil }
            let previous = change.previous.flatMap(SnoozeDeadline.init(stored:))
            record.snoozedUntil = previous?.isDue(at: now) == false ? change.previous : nil
            return record
        }
    }
}
