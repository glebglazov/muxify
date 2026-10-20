import Foundation

/// One Tag that `topics.tags` defines, with how it looks.
public struct TagDefinition: Equatable, Sendable {
    public let tag: Tag
    /// The written `color`, else a fixed colour made from the name, so two Tag Marks differ also without colours.
    public let color: MarkColor

    public init(tag: Tag, color: MarkColor? = nil) {
        self.tag = tag
        self.color = color ?? Self.color(named: tag.name)
    }

    private static let derivedColors: [SystemColorName] = [.blue, .orange, .red, .green, .yellow, .purple, .pink, .teal]

    /// FNV-1a, because `hashValue` changes with each launch.
    private static func color(named name: String) -> MarkColor {
        let hash = name.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return .single(.system(derivedColors[Int(hash % UInt32(derivedColors.count))]))
    }
}

/// A Tag on a Topic as the Sidebar and the palette show it.
public struct ShownTag: Equatable, Sendable {
    public let tag: Tag
    /// Nil for a Tag that the Config no longer defines: the record keeps it, and it shows dimmed, with no colour.
    public let definition: TagDefinition?
}

/// `topics.tags`: the only Tags that exist, in Config order. A Config without them has Tags off, so the value is
/// never empty.
public struct ConfigTags: Equatable, Sendable {
    public let definitions: [TagDefinition]

    /// Nil for no definitions: Tags are off.
    public init?(_ definitions: [TagDefinition]) {
        guard !definitions.isEmpty else { return nil }
        self.definitions = definitions
    }

    public func definition(of tag: Tag) -> TagDefinition? { definitions.first { $0.tag == tag } }

    public func defines(_ tag: Tag) -> Bool { definition(of: tag) != nil }

    /// The Tags in Config order, then those the Config no longer defines, A→Z.
    public func shown(_ tags: Set<Tag>) -> [ShownTag] {
        definitions.filter { tags.contains($0.tag) }.map { ShownTag(tag: $0.tag, definition: $0) }
            + tags.filter { !defines($0) }.sorted().map { ShownTag(tag: $0, definition: nil) }
    }

    /// The Tag that typed text names, in any case and with or without `#`.
    public func tag(typed text: String) -> Tag? {
        let name = (text.hasPrefix("#") ? String(text.dropFirst()) : text).lowercased()
        return definitions.first { $0.tag.name == name }?.tag
    }

    /// A Tag change that adds only Tags the Config defines. A Tag the Config no longer defines can stay or go.
    public func undefinedTags(added change: TopicTagChange, to tags: Set<Tag>) -> [Tag] {
        change.applied(to: tags).subtracting(tags).filter { !defines($0) }.sorted()
    }
}
