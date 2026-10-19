import Foundation

/// A short name on a Topic, written with `#`, such as `#backend`. It holds only lower case ASCII letters, digits
/// and `-`, so the suggestions have no near-duplicates such as `#Backend` beside `#backend`.
public struct Tag: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// Without the `#`, as the record stores it.
    public let name: String

    /// A name as a record stores it; nil when it is not a valid Tag.
    public init?(name: String) {
        guard !name.isEmpty, name.unicodeScalars.allSatisfy(Self.allowed.contains) else { return nil }
        self.name = name
    }

    /// A Tag as the user types it: the `#` before it is optional, and upper case becomes lower case.
    public init?(typed text: String) {
        self.init(name: (text.hasPrefix("#") ? String(text.dropFirst()) : text).lowercased())
    }

    public var description: String { "#" + name }

    public static func < (lhs: Tag, rhs: Tag) -> Bool { lhs.name < rhs.name }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        guard let tag = Tag(name: try value.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "expected a Tag: lower case letters, digits and -")
        }
        self = tag
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(name)
    }

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

    /// The Tags on the records that exist now, Settled Topics included, A→Z. There is no other list of Tags, so a
    /// Tag goes away with the last record that has it.
    public static func suggestions(from records: [TopicRecord]) -> [Tag] {
        Set(records.flatMap(\.tags)).sorted()
    }
}

/// How a request changes the Tags of a Topic.
public enum TopicTagChange: Codable, Hashable, Sendable {
    /// The Topic has exactly these Tags. An empty list removes every Tag.
    case set([Tag])
    case add([Tag])
    case remove([Tag])

    public func applied(to tags: Set<Tag>) -> Set<Tag> {
        switch self {
        case .set(let new): return Set(new)
        case .add(let new): return tags.union(new)
        case .remove(let old): return tags.subtracting(old)
        }
    }

    private enum SetCodingKeys: String, CodingKey { case _0 = "tags" }
    private enum AddCodingKeys: String, CodingKey { case _0 = "tags" }
    private enum RemoveCodingKeys: String, CodingKey { case _0 = "tags" }
}
