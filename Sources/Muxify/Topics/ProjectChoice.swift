import Foundation
import MuxifyCore

extension ProjectChoice {
    /// The search fields that let typing the folder name find a row whose title is an alias.
    var nameFields: [SearchField] { displayName == name ? [] : [.hidden(name)] }
}

extension ProjectRows {
    /// One header-less section, ranked by name then directory, then the row's last visit, then Config order.
    static func list(_ rows: [ProjectRow], query: String, visits: VisitLog) -> PickList<ProjectChoice> {
        FuzzyRanker.list([PickSectionInput(id: "projects", rule: .ranked(showsWhenEmpty: true), candidates: rows.map { row in
            PickCandidate(id: row.id, title: row.choice.displayName, fields: [.detail(row.choice.directory)] + row.choice.nameFields,
                          note: row.note, lastVisit: visits.last(.directory((row.choice.directory as NSString).standardizingPath)),
                          pick: .available(row.choice))
        })], query: FuzzyQuery(query))
    }
}
