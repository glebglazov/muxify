import Foundation

/// How a Topic lists its Sessions while the user has not ordered them by hand: `topics.session_order` in the Config.
public enum SessionOrder: String, CaseIterable, Sendable {
    case oldestFirst = "oldest_first"
    case newestFirst = "newest_first"
}

/// What the order of a Topic's Sessions reads from one live Session.
public struct TopicSessionKey: Equatable, Sendable {
    public let sessionID: String
    /// The Project path the Topic record names the Session by, `project_path` of its entry in `sessions`.
    public let projectPath: String
    /// tmux `#{session_created}`, in seconds since 1970.
    public let created: Int

    public init(sessionID: String, projectPath: String, created: Int) {
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.created = created
    }

    /// The key of the Session that `window` belongs to, named as `record` names it.
    public init(of window: TmuxWindow, record: TopicRecord?, projects: [Project]) {
        self.init(sessionID: window.sessionID, projectPath: TopicLocation(of: window, record: record, projects: projects).project.path,
                  created: window.sessionCreated)
    }
}

/// The one order of a Topic's live Sessions, which the Sidebar, the Command Palette and the record all follow.
/// By default the Sessions follow their creation time in the Config's order. Once the user moved one, the record
/// keeps the order: its `sessions` array, with `session_order: manual`. A Session the record does not name yet
/// then goes to the end that the Config's order gives new Sessions: the bottom for oldest first, the top for
/// newest first. A Topic names one Session per Project, so the record matches a Session by its Project path.
public enum TopicSessionOrder {
    public static func ordered<Item>(_ items: [Item], record: TopicRecord?, order: SessionOrder,
                                     key: (Item) -> TopicSessionKey) -> [Item] {
        let keyed = items.map { (item: $0, key: key($0)) }
        func byCreation(_ items: [(item: Item, key: TopicSessionKey)]) -> [(item: Item, key: TopicSessionKey)] {
            items.sorted { a, b in
                if a.key.created != b.key.created {
                    return order == .oldestFirst ? a.key.created < b.key.created : a.key.created > b.key.created
                }
                return a.key.sessionID < b.key.sessionID
            }
        }
        guard let record, record.hasManualSessionOrder else { return byCreation(keyed).map(\.item) }
        let positions = record.sessions.enumerated().reduce(into: [String: Int]()) { positions, entry in
            if let path = entry.element["project_path"]?.string { positions[standardized(path)] = positions[standardized(path)] ?? entry.offset }
        }
        let known = keyed.filter { positions[standardized($0.key.projectPath)] != nil }
            .sorted { a, b in
                let (first, second) = (positions[standardized(a.key.projectPath)]!, positions[standardized(b.key.projectPath)]!)
                return first != second ? first < second : (a.key.created, a.key.sessionID) < (b.key.created, b.key.sessionID)
            }
        let new = byCreation(keyed.filter { positions[standardized($0.key.projectPath)] == nil })
        return (order == .oldestFirst ? known + new : new + known).map(\.item)
    }

    static func standardized(_ path: String) -> String { (path as NSString).standardizingPath }
}

extension TopicRecord {
    /// Records a new Session's entry, in place of any entry of the same Project. A Topic in manual order puts it
    /// at the end that the Config's order gives new Sessions, so it shows where an unnamed Session would.
    mutating func recordingNewSession(_ entry: [String: JSONValue], order: SessionOrder) {
        let path = entry["project_path"]?.string.map(TopicSessionOrder.standardized)
        sessions.removeAll { $0["project_path"]?.string.map(TopicSessionOrder.standardized) == path }
        if hasManualSessionOrder && order == .newestFirst { sessions.insert(.object(entry), at: 0) }
        else { sessions.append(.object(entry)) }
    }
}
