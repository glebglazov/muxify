import MuxifyCore

/// What a key does in a "choose rows" step. Space marks only in an empty field, because titles have spaces.
enum ChooseRowsKey: Equatable {
    case markHighlighted, markShown

    init?(_ trigger: KeyTrigger, queryIsEmpty: Bool) {
        if trigger == KeyTrigger(modifiers: [], key: .special(.tab))
            || (queryIsEmpty && trigger == KeyTrigger(modifiers: [], key: .character(" "))) {
            self = .markHighlighted
        } else if trigger == KeyTrigger(modifiers: .command, key: .character("a")) {
            self = .markShown
        } else {
            return nil
        }
    }
}

/// A "choose rows" step: each row's payload is a `.mark` choice, and the flow keeps the marked rows in list
/// order through `PaletteFlow.markedIDs` and `marking(_:)`. The marks stay when the filter changes.
extension CommandPalette {
    func chooseRows(_ key: ChooseRowsKey) {
        switch key {
        case .markHighlighted: toggleSelected()
        case .markShown: toggleMarks(results.rows.compactMap { markID($0.pick.payload) })
        }
    }

    /// Marks every row of `ids`, or unmarks them when all of them are marked already.
    func toggleMarks(_ ids: [String]) {
        guard let flow, let marked = flow.markedIDs, !ids.isEmpty else { return }
        var marks = Set(marked)
        if marks.isSuperset(of: ids) { marks.subtract(ids) } else { marks.formUnion(ids) }
        let highlighted = selectedID
        replaceFlow(flow.marking(markOrder(flow).filter(marks.contains)))
        selectedID = highlighted
    }

    /// Nil when the row is not in a "choose rows" step.
    func isMarked(_ row: PickRow<PaletteItem>) -> Bool? {
        guard let marked = flow?.markedIDs, let id = markID(row.pick.payload) else { return nil }
        return marked.contains(id)
    }

    /// ↩ goes on with the marked rows, or with the highlighted row when nothing is marked.
    func continueWithMarks() {
        guard let flow, let marked = flow.markedIDs else { return }
        let chosen = marked.isEmpty ? [markID(selected(in: results)?.pick.payload)].compactMap { $0 } : marked
        guard !chosen.isEmpty else { return }
        query = ""
        replaceFlow(flow.continuing(with: chosen))
    }

    private func markID(_ item: PaletteItem?) -> String? {
        if case .choice(.mark(let id)) = item?.ref { return id }
        return nil
    }

    private func markOrder(_ flow: PaletteFlow) -> [String] {
        switch flow {
        case .snooze: return snoozeChoices.flatMap(\.candidates).compactMap { markID($0.pick.payload) }
        default: return []
        }
    }

    /// Visible: the Topics in the Topics list now, open and Dormant. Already Snoozed: the Snoozed Topics.
    var snoozeChoices: [PickSectionInput<PaletteItem>] {
        guard let topics = store?.topics else { return [] }
        func candidate(_ row: TopicsModel.Row, kind: PaletteItem.Kind) -> PickCandidate<PaletteItem>? {
            guard case .topic(let id) = row.id else { return nil }
            var trailing = topics.activeTopic == row.id ? "Active" : ""
            if case .snoozed(let wake) = row.kind { trailing = "until " + wake }
            return PickCandidate(id: row.id.accessibilityID, title: row.title,
                                 fields: (row.isDormant ? [.detail("Dormant")] : []) + row.sessions.map { .label($0.projectName) },
                                 trailing: trailing, mark: row.mark,
                                 pick: .available(PaletteItem(kind: kind, ref: .choice(.mark(id)))))
        }
        return [
            PickSectionInput(id: "visible", title: "Visible", rule: .ranked(showsWhenEmpty: true),
                             candidates: topics.rows.compactMap { candidate($0, kind: .topic) }),
            PickSectionInput(id: "snoozed", title: "Already Snoozed", rule: .ranked(showsWhenEmpty: true),
                             candidates: topics.snoozedRows.compactMap { candidate($0, kind: .snoozedTopic) }),
        ]
    }
}
