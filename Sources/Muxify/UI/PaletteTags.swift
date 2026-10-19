import MuxifyCore

/// A palette field that takes Tags: New Topic or Edit Tags. The complete Tags are chips that the flow keeps; the
/// text holds the words after them.
struct TagField {
    enum Mode {
        /// A word that starts with `#` is a Tag, and the other words are the title.
        case newTopic
        /// The field holds only the Tags of this Topic, so a word without `#` is a Tag too.
        case editTags(TopicRecord)
    }

    let mode: Mode
    var chipField: ChipField<Tag>

    init(mode: Mode, chips: [Tag] = []) {
        self.mode = mode
        chipField = ChipField(chips: chips)
    }

    func text(_ query: String) -> TagText { TagText(field: self, text: query) }
}

/// The text of a `TagField`. A Tag word is the draft while no space follows it, so the rows show the Tags that
/// match it.
struct TagText {
    let field: TagField
    let text: String

    private var words: [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }

    private func isTagWord(_ word: String) -> Bool {
        if case .editTags = field.mode { return true }
        return word.hasPrefix("#")
    }

    /// The word being typed, with its `#`; nil when the caret is not after a Tag word.
    var draft: String? {
        guard let last = words.last, text.last?.isWhitespace == false, isTagWord(last) else { return nil }
        return last.hasPrefix("#") ? last : "#" + last
    }

    /// The text without the draft, for when the draft becomes a chip.
    var withoutDraft: String {
        guard draft != nil, let range = text.range(of: words.last ?? "", options: .backwards) else { return text }
        return String(text[..<range.lowerBound])
    }

    /// The Tag words that ↩ cannot take, such as `#a.b`. New Topic keeps them in the title, so it refuses none.
    var refusedWords: [String] {
        guard case .editTags = field.mode else { return [] }
        return words.filter { Tag(typed: $0) == nil }
    }

    /// The chips, then each Tag word, once each.
    var tags: [Tag] {
        var tags = field.chipField.chips
        for tag in words.compactMap({ isTagWord($0) ? Tag(typed: $0) : nil }) where !tags.contains(tag) { tags.append(tag) }
        return tags
    }

    /// New Topic: the words that are not Tags.
    var title: String { words.filter { !isTagWord($0) || Tag(typed: $0) == nil }.joined(separator: " ") }
}

extension PaletteFlow {
    /// Nil in a step that takes no Tags.
    var tagField: TagField? {
        if case .text(.tags(let field)) = self { return field }
        return nil
    }
}

extension CommandPalette {
    /// The Tags that match the draft, A→Z, without the chips, then a New Tag row when the draft is a Tag that no
    /// record has. Empty while there is no draft.
    func tagRows(_ field: TagField) -> PickList<PaletteItem> {
        guard let store, let draft = field.text(query).draft else { return .empty }
        let records = store.topicWatcher.records
        let suggested = Tag.suggestions(from: records)
        let candidates = suggested.filter { !field.chipField.chips.contains($0) }.map { tag in
            let count = records.filter { $0.tags.contains(tag) }.count
            return PickCandidate(id: "tag-" + tag.name, title: tag.description, trailing: count == 1 ? "1 Topic" : "\(count) Topics",
                                 pick: .available(PaletteItem(kind: .tag, ref: .choice(.tag(tag)))), titlePlace: .tag)
        }
        var new: [PickCandidate<PaletteItem>] = []
        if let tag = Tag(typed: draft), !suggested.contains(tag), !field.chipField.chips.contains(tag) {
            new.append(PickCandidate(id: "new-tag", symbol: "＋", title: "New Tag “\(tag.name)”",
                                     pick: .available(PaletteItem(kind: .tag, ref: .choice(.tag(tag))))))
        }
        return FuzzyRanker.list([PickSectionInput(id: "tags", title: "Tags", rule: .ranked(showsWhenEmpty: true), candidates: candidates),
                                 PickSectionInput(id: "new-tag", rule: .fixed, candidates: new)], query: FuzzyQuery(draft))
    }

    /// ⇥ or ↩ on a Tag row, or a space after a complete Tag word: the draft becomes a chip.
    func addTagChip(_ tag: Tag) {
        guard var field = flow?.tagField else { return }
        query = field.text(query).withoutDraft
        field.chipField.append(tag)
        replaceFlow(.text(.tags(field)))
    }

    /// A space after a draft that is a Tag makes it a chip at once, so ⌫ then removes it whole. False when the
    /// draft is not a Tag, and the space goes into the field.
    func completeTagDraft() -> Bool {
        guard let field = flow?.tagField, let tag = field.text(query).draft.flatMap(Tag.init(typed:)) else { return false }
        addTagChip(tag)
        return true
    }

    /// While a draft is typed: how it becomes a chip. Then for New Topic what ↩ makes, and for Edit Tags what it
    /// changes.
    func tagNote(_ field: TagField) -> String? {
        let text = field.text(query)
        if text.draft != nil { return "⇥ or ↩ makes a chip · ⌫ in an empty field removes a chip" }
        func list(_ tags: [Tag]) -> String { tags.map(\.description).joined(separator: " ") }
        let tags = text.tags
        switch field.mode {
        case .newTopic:
            guard !tags.isEmpty else { return nil }
            let title = text.title.isEmpty ? "Untitled" : text.title
            return "Title: \(title) · Tags: \(list(tags)) · ↩ makes the Topic. Its first Project comes next."
        case .editTags(let topic):
            if let word = text.refusedWords.first { return "\(word) is not a Tag. Use lower case letters, digits and -." }
            let changes = [("Removes", topic.tags.sorted().filter { !tags.contains($0) }), ("Adds", tags.filter { !topic.tags.contains($0) })]
                .filter { !$0.1.isEmpty }.map { "\($0.0): \(list($0.1))" }
            let keys = field.chipField.selection == nil ? "← selects a Tag" : "← → move · ⌫ ⌦ remove the selected Tag"
            return (changes + [keys, "↩ saves"] + (changes.isEmpty ? ["esc changes nothing"] : []))
                .joined(separator: " · ")
        }
    }
}
