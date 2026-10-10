import Foundation
import MuxifyCore

/// A Project or Worktree row's ↩: go to the Session there, or start one. The store resolves it when
/// pressed, with the Windows of that moment, so two presses end on one Session.
struct OpenDirectory: Hashable {
    let directory: String
    /// The row name, which names a created Session.
    let name: String
    let reach: SessionResolver.Reach
}

/// Which live Sessions a Project or Worktree row holds, and what ↩ on the row does. One rule for the
/// row's marker when the list is built, the Sessions-mode join, and the store's choice at ↩ time.
/// Built once per list: it finds each Session's nearest row up front, so a lookup costs one row, not a
/// scan of every Window against every row.
struct SessionResolver {
    enum Reach: Hashable {
        /// Sessions of open Topics do not count: the Topic row is the way to them.
        case noTopicOnly
        case anySession
    }

    enum Target: Equatable {
        case go(TmuxWindow)
        case create(name: String)
    }

    private let openTopicIDs: Set<String>
    private let visits: VisitLog
    private let sessionNames: Set<String>
    /// Standardized row directory to the Windows whose Session starts there or inside it, in tmux order.
    private let windowsByRow: [String: [TmuxWindow]]

    init(windows: [TmuxWindow], openTopicIDs: Set<String>, projects: [Project], visits: VisitLog) {
        self.openTopicIDs = openTopicIDs
        self.visits = visits
        sessionNames = Set(windows.map(\.sessionName))
        let roots = projects.flatMap(ProjectChoice.choices).map { ($0.directory as NSString).standardizingPath }
        var rowOfPath: [String: String?] = [:]
        var windowsByRow: [String: [TmuxWindow]] = [:]
        for window in windows {
            let row = rowOfPath[window.sessionPath] ?? {
                // The nearest row wins, so a Session in a Worktree inside a bare Project folder belongs to the Worktree row only.
                let path = (window.sessionPath as NSString).standardizingPath
                let row = roots.filter { path == $0 || path.hasPrefix($0 + "/") }.max { $0.count < $1.count }
                rowOfPath[window.sessionPath] = row
                return row
            }()
            if let row { windowsByRow[row, default: []].append(window) }
        }
        self.windowsByRow = windowsByRow
    }

    /// The live Sessions whose start directory is `directory` or inside it, as groups of their Windows in
    /// tmux order. The Session visited last comes first, then the most recently active one.
    func sessions(in directory: String, reach: Reach) -> [[TmuxWindow]] {
        var sessions: [[TmuxWindow]] = []
        for window in windowsByRow[(directory as NSString).standardizingPath] ?? [] {
            if reach == .noTopicOnly, let id = window.topicID, openTopicIDs.contains(id) { continue }
            if let index = sessions.firstIndex(where: { $0[0].sessionID == window.sessionID }) {
                sessions[index].append(window)
            } else {
                sessions.append([window])
            }
        }
        return sessions.enumerated().sorted { lhs, rhs in
            let left = visits.last(.session(name: lhs.element[0].sessionName))
            let right = visits.last(.session(name: rhs.element[0].sessionName))
            switch (left, right) {
            case (let left?, let right?) where left != right: return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if lhs.element[0].sessionActivity != rhs.element[0].sessionActivity {
                    return lhs.element[0].sessionActivity > rhs.element[0].sessionActivity
                }
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// ↩ on the row: the active Window of the Session visited last, or a new Session named after the row.
    func target(directory: String, name: String, reach: Reach) -> Target {
        if let session = sessions(in: directory, reach: reach).first {
            return .go(session.first(where: \.isActive) ?? session[0])
        }
        return .create(name: Self.sessionName(name, taken: sessionNames))
    }

    /// The row name as tmux takes it (see `Project.sessionName`); "-2", "-3", ... while a Session has the name.
    static func sessionName(_ rowName: String, taken: Set<String>) -> String {
        let base = Project.sessionName(rowName)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base)-\(number)") { number += 1 }
        return "\(base)-\(number)"
    }
}
