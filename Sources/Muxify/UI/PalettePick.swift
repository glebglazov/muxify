import MuxifyCore

/// A Topic that a pick step lists, with the Tags that a Tag chip matches.
struct PickableTopic: Equatable {
    let id: String
    let tags: [Tag]
}

/// A chip of a pick step: one Topic, or a Tag that names every Topic that has it.
enum PickChip: Hashable {
    case tag(Tag)
    case topic(String)

    /// The Topics that `chips` name, once each, in the order of `topics`.
    static func topicIDs(_ chips: [PickChip], in topics: [PickableTopic]) -> [String] {
        topics.filter { topic in chips.contains { $0.names(topic) } }.map(\.id)
    }

    /// The first Tag chip of `chips` that names the Topic; nil when no Tag chip names it.
    static func coveringTag(of id: String, in chips: [PickChip], topics: [PickableTopic]) -> Tag? {
        guard let topic = topics.first(where: { $0.id == id }) else { return nil }
        for case .tag(let tag) in chips where topic.tags.contains(tag) { return tag }
        return nil
    }

    private func names(_ topic: PickableTopic) -> Bool {
        switch self {
        case .tag(let tag): topic.tags.contains(tag)
        case .topic(let id): topic.id == id
        }
    }
}

/// The pick step of Snooze Topics (ADR 0025): ↩ on a row makes it a chip, and the go-on row opens the "until" step.
extension CommandPalette {
    /// The Topics list, then the Snoozed Topics. Settled Topics are not in it.
    var pickableTopics: [PickableTopic] {
        guard let topics = store?.topics else { return [] }
        return (topics.rows + topics.snoozedRows).compactMap { row in
            guard case .topic(let id) = row.id else { return nil }
            return PickableTopic(id: id, tags: row.tags)
        }
    }

    func snoozeTopicIDs(_ draft: SnoozeDraft) -> [String] {
        PickChip.topicIDs(draft.chipField.chips, in: pickableTopics)
    }

    /// The go-on row while the query is empty and a chip exists. Then Tags, Topics and Already Snoozed, without
    /// the picked rows. Then, for a query that is not a Tag, one row that picks every Topic it matches.
    func pickRows(_ draft: SnoozeDraft) -> PickList<PaletteItem> {
        guard let topics = store?.topics else { return .empty }
        let picked = draft.chipField.chips
        let pickable = pickableTopics
        func candidate(_ row: TopicsModel.Row, kind: PaletteItem.Kind) -> PickCandidate<PaletteItem>? {
            guard case .topic(let id) = row.id, !picked.contains(.topic(id)) else { return nil }
            var trailing = topics.activeTopic == row.id ? "Active" : ""
            if case .snoozed(let wake) = row.kind { trailing = "until " + wake }
            if let tag = PickChip.coveringTag(of: id, in: picked, topics: pickable) { trailing = "in \(tag)" }
            return PickCandidate(id: row.id.accessibilityID, title: row.title,
                                 fields: (row.idleLabel.map { [.detail($0)] } ?? []) + row.sessions.map { .label($0.projectName) }
                                    + row.tags.map(SearchField.tag),
                                 trailing: trailing, mark: row.mark,
                                 pick: .available(PaletteItem(kind: kind, ref: .choice(.pick([.topic(id)])))))
        }
        let tags = Set(pickable.flatMap(\.tags)).sorted().filter { !picked.contains(.tag($0)) }.map { tag in
            let count = PickChip.topicIDs([.tag(tag)], in: pickable).count
            return PickCandidate(id: "tag-" + tag.name, title: tag.description, fields: [.hidden(tag.name)],
                                 trailing: count == 1 ? "1 Topic" : "\(count) Topics",
                                 pick: .available(PaletteItem(kind: .tag, ref: .choice(.pick([.tag(tag)])))), titlePlace: .tag)
        }
        var sections: [PickSectionInput<PaletteItem>] = []
        if query.isEmpty, !picked.isEmpty {
            let count = snoozeTopicIDs(draft).count
            sections.append(PickSectionInput(id: "go-on", rule: .fixed, candidates: [
                PickCandidate(id: "snooze-picked", title: "→ Snooze \(count == 1 ? "1 Topic" : "\(count) Topics")…",
                              pick: .available(PaletteItem(kind: .command, ref: .choice(.snoozePicked)))),
            ]))
        }
        sections += [
            PickSectionInput(id: "tags", title: "Tags", rule: .ranked(showsWhenEmpty: true), candidates: tags),
            PickSectionInput(id: "topics", title: "Topics", rule: .ranked(showsWhenEmpty: true),
                             candidates: topics.rows.compactMap { candidate($0, kind: .topic) }),
            PickSectionInput(id: "snoozed", title: "Already Snoozed", rule: .ranked(showsWhenEmpty: true),
                             candidates: topics.snoozedRows.compactMap { candidate($0, kind: .snoozedTopic) }),
        ]
        let list = FuzzyRanker.list(sections, query: FuzzyQuery(query))
        guard !query.isEmpty, !query.hasPrefix("#") else { return list }
        let matches = list.rows.compactMap { row -> String? in
            guard let id = topicID(of: row), PickChip.coveringTag(of: id, in: picked, topics: pickable) == nil else { return nil }
            return id
        }
        guard matches.count >= 2 else { return list }
        let all = PickCandidate(id: "pick-all", title: "＋ All \(matches.count) matches for “\(query)”",
                                pick: .available(PaletteItem(kind: .command, ref: .choice(.pick(matches.map(PickChip.topic))))))
        return PickList(sections: list.sections + FuzzyRanker.list([PickSectionInput(id: "pick-all", rule: .fixed, candidates: [all])],
                                                                    query: FuzzyQuery("")).sections)
    }

    /// A Topic row of the pick step that a picked Tag already names. It stays, dim.
    func isCovered(_ row: PickRow<PaletteItem>) -> Bool {
        guard case .snooze(let draft)? = flow, draft.step == .pick, let id = topicID(of: row) else { return false }
        return PickChip.coveringTag(of: id, in: draft.chipField.chips, topics: pickableTopics) != nil
    }

    private func topicID(of row: PickRow<PaletteItem>) -> String? {
        guard case .choice(.pick(let chips))? = row.pick.payload?.ref, chips.count == 1, case .topic(let id) = chips[0] else { return nil }
        return id
    }

    /// ↩ on a row: its chips join the field, and the query clears.
    func pick(_ chips: [PickChip]) {
        guard case .snooze(var draft) = flow, draft.step == .pick else { return }
        chips.forEach { draft.chipField.append($0) }
        query = ""
        replaceFlow(.snooze(draft))
    }

    /// ↩ on the go-on row opens the "until" step with the chips kept.
    func snoozePicked() {
        guard case .snooze(var draft) = flow, draft.step == .pick, !snoozeTopicIDs(draft).isEmpty else { return }
        query = ""
        draft.step = .until
        replaceFlow(.snooze(draft))
    }
}
