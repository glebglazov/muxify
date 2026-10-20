import Foundation
import MuxifyCore

/// What a visit is to. No Topic is a Topic key too.
enum VisitKey: Hashable {
    case topic(TopicGroupID)
    case session(name: String)
    /// A ProjectChoice directory's real path.
    case directory(String)

    var stored: String {
        switch self {
        case .topic(.topic(let id)): return "topic:" + id
        // A Locked Session is a No Topic Session, and its Session visits are kept by name.
        case .topic(.noTopic), .topic(.locked): return "topic:-"
        case .session(let name): return "session:" + name
        case .directory(let path): return "path:" + path
        }
    }

    init?(stored: String) {
        guard let colon = stored.firstIndex(of: ":") else { return nil }
        let value = String(stored[stored.index(after: colon)...])
        switch stored[..<colon] {
        case "topic": self = .topic(value == "-" ? .noTopic : .topic(value))
        case "session": self = .session(name: value)
        case "path": self = .directory(value)
        default: return nil
        }
    }
}

/// Every visit time, kept across restarts in one UserDefaults key. One writer: WorkspaceStore on the main thread.
struct VisitLog: Equatable {
    static let defaultsKey = "visits"
    static let legacyProjectKey = "projectLastOpened"
    /// Set once the stored directory keys are real paths. Before, they were spelled as the Config wrote them.
    static let realPathsKey = "visitPathsAreReal"
    /// Only the newest entries are saved, so the key cannot grow without bound.
    static let capacity = 2000

    private(set) var times: [VisitKey: Date] = [:]
    /// The keys the last `record` stamped; the same look at the same place is not a new visit.
    private var lastRecorded: Set<VisitKey> = []

    init() {}

    /// Reads the stored visits. The first launch after an upgrade resolves the directory keys to real paths on this
    /// Mac, where two spellings of one folder keep the later visit, imports the old per-Project `projectLastOpened`
    /// times as directory visits, saves, and removes that key.
    init(defaults: UserDefaults) {
        let resolves = !defaults.bool(forKey: Self.realPathsKey)
        for (key, value) in defaults.dictionary(forKey: Self.defaultsKey) ?? [:] {
            guard let key = VisitKey(stored: key), let seconds = value as? Double else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            if resolves, case .directory(let path) = key { keepLater(.directory(Folder.local(path).real), date) } else { times[key] = date }
        }
        let legacy = defaults.dictionary(forKey: Self.legacyProjectKey) as? [String: Date]
        for (path, date) in legacy ?? [:] { keepLater(.directory(Folder.local(path).real), date) }
        guard resolves || legacy != nil else { return }
        defaults.removeObject(forKey: Self.legacyProjectKey)
        defaults.set(true, forKey: Self.realPathsKey)
        save(to: defaults)
    }

    private mutating func keepLater(_ key: VisitKey, _ date: Date) {
        if times[key].map({ $0 < date }) ?? true { times[key] = date }
    }

    func save(to defaults: UserDefaults) {
        let newest = times.sorted { $0.value > $1.value }.prefix(Self.capacity)
        defaults.set(Dictionary(uniqueKeysWithValues: newest.map { ($0.key.stored, $0.value.timeIntervalSince1970) }),
                     forKey: Self.defaultsKey)
    }

    func last(_ key: VisitKey) -> Date? { times[key] }

    /// One visit: the Window's group, its Session, and the Project or Worktree that holds the Session's
    /// start directory. Returns false when the same place was recorded last, so the caller saves only on a change.
    /// `folders` resolves the Session's path on the machine that runs it.
    mutating func record(_ window: TmuxWindow, group: TopicGroupID, projects: [Project], folders: FolderResolver, at now: Date) -> Bool {
        var keys: Set<VisitKey> = [.topic(group), .session(name: window.sessionName)]
        if let choice = ProjectChoice.containing(folders.folder(window.sessionPath), in: projects) {
            keys.insert(.directory(choice.directory.real))
        }
        guard keys != lastRecorded else { return false }
        lastRecorded = keys
        for key in keys { times[key] = now }
        return true
    }
}

/// "now", "2m", "1h", "3d" for a right column.
enum VisitAge {
    static func short(since: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(since))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
