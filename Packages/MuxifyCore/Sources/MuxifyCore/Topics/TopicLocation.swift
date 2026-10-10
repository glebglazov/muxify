import Foundation

/// Where a Window's Session belongs in its Topic: the Project it works on, whether that is the Home Project,
/// and the Worktree when the record remembers one. The longest remembered directory that holds the Session
/// directory decides; without one, the Config Project that holds it, else the directory itself.
public struct TopicLocation {
    public let project: Project
    public let isHome: Bool
    public let worktreePath: String?

    public init(of window: TmuxWindow, record: TopicRecord?, projects: [Project]) {
        let directory = (window.sessionPath as NSString).standardizingPath
        var candidates: [(directory: String, project: String, worktreePath: String?)] = []
        if let home = record?.homeProject { candidates.append((home, home, nil)) }
        for session in record?.sessions ?? [] {
            guard let path = session["project_path"]?.string else { continue }
            candidates.append((path, path, nil))
            if let worktree = session["worktree_path"]?.string { candidates.append((worktree, path, worktree)) }
        }
        let match = candidates.filter {
            let path = ($0.directory as NSString).standardizingPath
            return !path.isEmpty && (directory == path || directory.hasPrefix(path == "/" ? path : path + "/"))
        }.max { ($0.directory.count, $0.worktreePath != nil ? 1 : 0) < ($1.directory.count, $1.worktreePath != nil ? 1 : 0) }
        let path = match?.project ?? Project.containing(directory, in: projects)?.path ?? directory
        let project = Project.named(at: path, in: projects)
        let isHome = match.map { ($0.project as NSString).standardizingPath == (record?.homeProject as NSString?)?.standardizingPath } ?? false
        self.project = project.name.isEmpty ? Project(path: path, name: "Unknown Project") : project
        self.isHome = isHome
        worktreePath = match?.worktreePath
    }
}
