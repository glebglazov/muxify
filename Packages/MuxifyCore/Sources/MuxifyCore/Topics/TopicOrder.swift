import Foundation

public enum TopicPlacement: Equatable {
    case before(String)
    case after(String)

    public var anchorID: String {
        switch self {
        case .before(let id), .after(let id): return id
        }
    }
}

public enum TopicOrder {
    public enum Failure: Error, CustomStringConvertible {
        case sourceUnavailable, anchorUnavailable

        public var description: String {
            switch self {
            case .sourceUnavailable: return "The Topic is no longer open."
            case .anchorUnavailable: return "The Topic at the drop position is no longer open."
            }
        }
    }

    /// The Pinned Topics first, then the others; each part in its own hand-set order.
    public static func sorted(_ records: [TopicRecord]) -> [TopicRecord] {
        records.filter { $0.settledAt == nil }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if ($0.createdAt ?? "") != ($1.createdAt ?? "") { return ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            return $0.id < $1.id
        }
    }

    /// A move stays among the Topics with the same pin: an anchor in the other part puts the Topic at the edge of its own.
    public static func moving(_ id: String, to placement: TopicPlacement, in records: [TopicRecord]) throws -> [TopicRecord] {
        let original = sorted(records)
        guard let source = original.first(where: { $0.id == id }) else { throw Failure.sourceUnavailable }
        guard let anchor = original.first(where: { $0.id == placement.anchorID }) else { throw Failure.anchorUnavailable }
        let zone = original.filter { $0.isPinned == source.isPinned }
        let target: TopicPlacement
        if anchor.isPinned == source.isPinned { target = placement }
        else { target = source.isPinned ? .after(zone.last!.id) : .before(zone.first!.id) }
        guard id != target.anchorID else { return [] }
        var ordered = zone.filter { $0.id != id }
        let anchorIndex = ordered.firstIndex { $0.id == target.anchorID }!
        let index: Int
        switch target {
        case .before: index = anchorIndex
        case .after: index = anchorIndex + 1
        }
        ordered.insert(source, at: index)
        guard ordered.map(\.id) != zone.map(\.id) else { return [] }
        return placing(source, at: index, in: ordered, others: original.filter { $0.isPinned != source.isPinned })
    }

    /// Pin puts the Topic last among the Pinned Topics; Unpin puts it first among the others.
    public static func pinning(_ id: String, _ pinned: Bool, in records: [TopicRecord]) throws -> [TopicRecord] {
        let original = sorted(records)
        guard var source = original.first(where: { $0.id == id }) else { throw Failure.sourceUnavailable }
        guard source.isPinned != pinned else { return [] }
        source.isPinned = pinned
        var zone = original.filter { $0.isPinned == pinned }
        let index = pinned ? zone.count : 0
        zone.insert(source, at: index)
        return placing(source, at: index, in: zone, others: original.filter { $0.isPinned != pinned && $0.id != id })
    }

    /// The order that puts a Topic first among the Topics with its pin.
    public static func firstOrder(in records: [TopicRecord], pinned: Bool) -> Double? {
        rank(between: nil, and: sorted(records).first { $0.isPinned == pinned }.map(rank))
    }

    public static func prepending(_ record: TopicRecord, in records: [TopicRecord]) -> [TopicRecord] {
        var record = record
        if let value = firstOrder(in: records, pinned: record.isPinned) {
            record.order = value
            return [record]
        }
        record.order = -1
        return normalized(sorted(records)) + [record]
    }

    /// Gives `source`, at `index` in `zone`, an order between its neighbors there, or renumbers every open Topic
    /// when no order fits between them.
    private static func placing(_ source: TopicRecord, at index: Int, in zone: [TopicRecord], others: [TopicRecord]) -> [TopicRecord] {
        if let value = rank(between: index > 0 ? rank(zone[index - 1]) : nil,
                            and: index + 1 < zone.count ? rank(zone[index + 1]) : nil) {
            var placed = source
            placed.order = value
            return [placed]
        }
        let renumbered = normalized(source.isPinned ? zone + others : others + zone)
        return renumbered.contains { $0.id == source.id } ? renumbered : renumbered + [source]
    }

    private static func rank(_ record: TopicRecord) -> Double {
        guard let order = record.order, order.isFinite else { return 0 }
        return order
    }

    private static func rank(between lower: Double?, and upper: Double?) -> Double? {
        let candidate: Double
        switch (lower, upper) {
        case (nil, nil): return -1
        case (nil, let upper?): candidate = upper - 1 < upper ? upper - 1 : upper.nextDown
        case (let lower?, nil): candidate = lower + 1 > lower ? lower + 1 : lower.nextUp
        case (let lower?, let upper?):
            guard lower < upper else { return nil }
            let midpoint = lower / 2 + upper / 2
            candidate = midpoint > lower && midpoint < upper ? midpoint : lower.nextUp
        }
        guard candidate.isFinite, lower.map({ candidate > $0 }) ?? true,
              upper.map({ candidate < $0 }) ?? true else { return nil }
        return candidate
    }

    private static func normalized(_ records: [TopicRecord]) -> [TopicRecord] {
        records.enumerated().compactMap { index, record in
            guard record.order != Double(index) else { return nil }
            var record = record
            record.order = Double(index)
            return record
        }
    }
}
