import Foundation

/// One open Topic as `topic show` reports it: its record, and its live Sessions with their Windows and Panes.
public struct TopicDetail: Codable, Hashable, Sendable {
    public struct ProjectEntry: Codable, Hashable, Sendable {
        /// The Config's alias, else the Project's name.
        public var label: String
        public var path: String

        public init(label: String, path: String) {
            self.label = label
            self.path = path
        }
    }

    public struct WorktreeEntry: Codable, Hashable, Sendable {
        public var path: String
        /// Nil when HEAD is detached or the branch is unknown.
        public var branch: String?
        /// The full id of the commit that the Topic started this Worktree at. Nil when the Topic did not make the
        /// Worktree, or made it before records stored `base`.
        public var base: String?

        public init(path: String, branch: String?, base: String? = nil) {
            self.path = path
            self.branch = branch
            self.base = base
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(path, forKey: .path)
            try values.encode(branch, forKey: .branch)
            try values.encode(base, forKey: .base)
        }

        private enum CodingKeys: String, CodingKey { case path, branch, base }
    }

    public struct Window: Codable, Hashable, Sendable {
        public var id: String
        public var index: Int
        public var name: String
        public var active: Bool
        public var panes: [PaneSummary]

        public init(id: String, index: Int, name: String, active: Bool, panes: [PaneSummary]) {
            self.id = id
            self.index = index
            self.name = name
            self.active = active
            self.panes = panes
        }
    }

    public struct Session: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var project: ProjectEntry
        /// Nil when the Session uses the Project folder.
        public var worktree: WorktreeEntry?
        public var windows: [Window]

        public init(id: String, name: String, project: ProjectEntry, worktree: WorktreeEntry?, windows: [Window]) {
            self.id = id
            self.name = name
            self.project = project
            self.worktree = worktree
            self.windows = windows
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(name, forKey: .name)
            try values.encode(project, forKey: .project)
            try values.encode(worktree, forKey: .worktree)
            try values.encode(windows, forKey: .windows)
        }

        private enum CodingKeys: String, CodingKey { case id, name, project, worktree, windows }
    }

    public var id: String
    /// The label `topic list` prints.
    public var label: String
    public var title: String?
    public var slug: String?
    public var homeProject: String?
    public var createdAt: String?
    public var snoozedUntil: String?
    /// The Sessions whose `@muxify_topic` names this Topic, in tmux order. Empty for a Dormant Topic.
    public var sessions: [Session]

    public init(id: String, label: String, title: String?, slug: String?, homeProject: String?, createdAt: String?,
                snoozedUntil: String?, sessions: [Session]) {
        self.id = id
        self.label = label
        self.title = title
        self.slug = slug
        self.homeProject = homeProject
        self.createdAt = createdAt
        self.snoozedUntil = snoozedUntil
        self.sessions = sessions
    }

    /// `branches` reads each Worktree's branch now; a Worktree it cannot read keeps the branch the record remembers.
    public init(record: TopicRecord, snapshot: TmuxSnapshot, projects: [Project], branches: TopicBranches) {
        let windows = snapshot.windows.filter { $0.topicID == record.id }
        let sessionIDs = windows.map(\.sessionID).reduce(into: [String]()) { ids, id in
            if !ids.contains(id) { ids.append(id) }
        }
        let sessions = sessionIDs.compactMap { sessionID -> Session? in
            let members = windows.filter { $0.sessionID == sessionID }
            guard let first = members.first else { return nil }
            let location = TopicLocation(of: first, record: record, projects: projects)
            let worktree = location.worktreePath.map { path in
                let remembered = record.sessions.first { $0["worktree_path"]?.string == path }
                return WorktreeEntry(path: path, branch: branches[path] ?? remembered?["branch"]?.string,
                                     base: remembered?[TopicWorktrees.baseKey]?.string)
            }
            return Session(id: sessionID, name: first.sessionName,
                           project: ProjectEntry(label: location.project.displayName, path: location.project.path),
                           worktree: worktree,
                           windows: members.map { window in
                               Window(id: window.id, index: window.index, name: window.name, active: window.isActive,
                                      panes: snapshot.panes.filter { $0.windowID == window.id }.map(PaneSummary.init))
                           })
        }
        self.init(id: record.id, label: TopicSummary(record: record).label, title: record.title, slug: record.slug,
                  homeProject: record.homeProject, createdAt: record.createdAt, snoozedUntil: record.snoozedUntil,
                  sessions: sessions)
    }

    // Synthesized encoding leaves out a nil key. A reader gets every key, with null for a field the record does not have.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(label, forKey: .label)
        try values.encode(title, forKey: .title)
        try values.encode(slug, forKey: .slug)
        try values.encode(homeProject, forKey: .homeProject)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(snoozedUntil, forKey: .snoozedUntil)
        try values.encode(sessions, forKey: .sessions)
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, title, slug, sessions
        case homeProject = "home_project", createdAt = "created_at", snoozedUntil = "snoozed_until"
    }
}
