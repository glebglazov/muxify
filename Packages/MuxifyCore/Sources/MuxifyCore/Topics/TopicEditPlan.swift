import Foundation

struct TopicEdit: Sendable {
    public enum Selection: Equatable, Sendable {
        case unchanged
        case sessionID(String)
        case sessionName(String)
        case paneID(String)
        /// An open Topic with no Session: the terminal area offers to add a Project to it.
        case emptyTopic(String)
    }

    public let record: TopicRecord?
    public var newWorktree: TopicPlan.NewWorktree? = nil
    public let commands: [TopicPlan.Command]
    public let selection: Selection
    enum Completion: Sendable {
        case save(TopicRecord)
        case forget(String)
        var topicID: String {
            switch self { case .save(let record): return record.id; case .forget(let id): return id }
        }
    }
    var completion: Completion?

    public init(record: TopicRecord?, newWorktree: TopicPlan.NewWorktree? = nil, commands: [TopicPlan.Command], selection: Selection, completion: Completion? = nil) {
        self.record = record
        self.newWorktree = newWorktree
        self.commands = commands
        self.selection = selection
        self.completion = completion
    }
}

enum TopicEditFailure: Error, CustomStringConvertible {
    case destinationUnavailable, sourceUnavailable, duplicateProject, invalidProject
    case sessionNameInUse, invalidTmuxResponse, sessionUnavailable

    public var description: String {
        switch self {
        case .destinationUnavailable: return "The Topic is no longer open."
        case .sourceUnavailable: return "The source Pane or Window is no longer available."
        case .duplicateProject: return "The Topic has more than one Session in the same Project."
        case .invalidProject: return "The Project needs a directory and a name that tmux accepts."
        case .sessionNameInUse: return "The Topic's Session name is already in use."
        case .invalidTmuxResponse: return "tmux did not return the expected Pane or Window identity."
        case .sessionUnavailable: return "The Session is no longer in the Topic."
        }
    }
}

private enum TopicEditProjects {
    public static func path(_ value: String) -> String { (value as NSString).standardizingPath }

    public static func validate(_ project: Project) throws {
        guard !project.path.isEmpty, !project.name.isEmpty,
              !project.name.contains("."), !project.name.contains(":"),
              !project.name.contains("\n"), !project.name.contains("\0") else {
            throw TopicEditFailure.invalidProject
        }
    }

    public static func project(at path: String, projects: [Project]) -> Project {
        Project.containing(path, in: projects)
            ?? Project(path: self.path(path), name: (self.path(path) as NSString).lastPathComponent)
    }

    public static func sessions(in windows: [TmuxWindow], topic: TopicRecord) -> [TmuxWindow] {
        var ids: Set<String> = []
        return windows.filter { $0.topicID == topic.id && ids.insert($0.sessionID).inserted }
    }
}

struct TopicRenamePlan {
    public let edit: TopicEdit

    public init(topic: TopicRecord, title: String, records: [TopicRecord], windows: [TmuxWindow], projects: [Project]) throws {
        let members = TopicEditProjects.sessions(in: windows, topic: topic)
        let locations = members.map { TopicLocation(of: $0, record: topic, projects: projects).project }
        guard Set(locations.map { TopicEditProjects.path($0.path) }).count == locations.count else {
            throw TopicEditFailure.duplicateProject
        }
        guard Set(locations.map(\.name)).count == locations.count else {
            throw TopicEditFailure.sessionNameInUse
        }
        var affected = locations
        if let home = topic.homeProject { affected.append(TopicEditProjects.project(at: home, projects: projects)) }
        for session in topic.sessions {
            if let path = session["project_path"]?.string { affected.append(TopicEditProjects.project(at: path, projects: projects)) }
        }
        for project in affected { try TopicEditProjects.validate(project) }
        let home = affected.first ?? Project(path: "/", name: "topic")
        let memberIDs = Set(members.map(\.sessionID))
        let names = Set(windows.filter { !memberIDs.contains($0.sessionID) }.map(\.sessionName))
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = TopicNaming.slug(title: title, project: home, records: records, sessionNames: names,
                                   excludingTopicID: topic.id, projectNames: Set(affected.map(\.name)))
        var record = topic
        record.title = title.isEmpty ? nil : title
        record.slug = slug
        let commands = zip(members, locations).map { window, project in
            TopicPlan.Command.tmux(["rename-session", "-t", window.sessionID, project.name + "/" + slug])
        }
        edit = TopicEdit(record: record, commands: commands, selection: .unchanged)
    }
}

/// A change to the order of a Topic's Sessions. It writes only the record: tmux has no order of Sessions.
struct TopicSessionOrderPlan {
    public let edit: TopicEdit

    /// Moves a live Session before or after another one, as the Topic lists them now, and keeps that order.
    public init(moving sessionID: String, to placement: TopicSessionPlacement, topic: TopicRecord, windows: [TmuxWindow],
                projects: [Project], order: SessionOrder) throws {
        let key = { (window: TmuxWindow) in TopicSessionKey(of: window, record: topic, projects: projects) }
        let shown = TopicSessionOrder.ordered(TopicEditProjects.sessions(in: windows, topic: topic), record: topic, order: order, key: key)
        guard let moved = shown.first(where: { $0.sessionID == sessionID }),
              shown.contains(where: { $0.sessionID == placement.anchor.rawValue }) else { throw TopicEditFailure.sessionUnavailable }
        guard sessionID != placement.anchor.rawValue else {
            edit = TopicEdit(record: nil, commands: [], selection: .unchanged)
            return
        }
        var ordered = shown.filter { $0.sessionID != sessionID }
        let anchor = ordered.firstIndex { $0.sessionID == placement.anchor.rawValue }!
        switch placement {
        case .before: ordered.insert(moved, at: anchor)
        case .after: ordered.insert(moved, at: anchor + 1)
        }
        let paths = ordered.map { TopicSessionOrder.standardized(key($0).projectPath) }
        func path(_ entry: JSONValue) -> String? { entry["project_path"]?.string.map(TopicSessionOrder.standardized) }
        var record = topic
        // A remembered entry with no live Session keeps its place after the live ones.
        record.sessions = paths.map { live in topic.sessions.first { path($0) == live } ?? .object(["project_path": .string(live)]) }
            + topic.sessions.filter { path($0).map { !paths.contains($0) } ?? true }
        record.hasManualSessionOrder = true
        edit = TopicEdit(record: record, commands: [], selection: .unchanged)
    }

    /// Lets the Topic list its Sessions by creation again.
    public init(sortingByCreation topic: TopicRecord) {
        var record = topic
        record.hasManualSessionOrder = false
        edit = TopicEdit(record: record, commands: [], selection: .unchanged)
    }
}

struct TopicProjectPlan {
    public let edit: TopicEdit

    public init(topic: TopicRecord, project: Project, workingCopy: TopicWorkingCopy, windows: [TmuxWindow], projects: [Project],
                order: SessionOrder = .oldestFirst) throws {
        try TopicEditProjects.validate(project)
        let path = TopicEditProjects.path(project.path)
        let members = TopicEditProjects.sessions(in: windows, topic: topic).filter {
            TopicEditProjects.path(TopicLocation(of: $0, record: topic, projects: projects).project.path) == path
        }
        guard members.count <= 1 else { throw TopicEditFailure.duplicateProject }
        if let existing = members.first {
            edit = TopicEdit(record: nil, commands: [], selection: .sessionID(existing.sessionID))
            return
        }
        let slug = topic.slug ?? TopicNaming.slugify(topic.title ?? "topic")
        let name = project.name + "/" + slug
        guard !windows.contains(where: { $0.sessionName == name }) else { throw TopicEditFailure.sessionNameInUse }
        var record = topic
        if record.homeProject == nil { record.homeProject = project.path }
        let remembered = record.sessions.first { session in
            session["project_path"]?.string.map { TopicEditProjects.path($0) == path } ?? false
        }
        var session: [String: JSONValue] = [:]
        if case .object(let fields)? = remembered { session = fields }
        let start = workingCopy.sessionStart(in: project, slug: slug)
        for key in ["worktree_path", "branch", TopicWorktrees.createdKey, TopicWorktrees.baseKey] { session[key] = nil }
        session.merge(start.worktreeFields) { _, new in new }
        session["project_path"] = .string(path)
        record.recordingNewSession(session, order: order)
        edit = TopicEdit(record: record, newWorktree: start.newWorktree, commands: [
            .tmux(["new-session", "-d", "-s", name, "-c", start.directory]),
            .tmux(["set-option", "-t", "=" + name + ":", "@muxify_topic", topic.id]),
        ], selection: .sessionName(name))
    }
}

struct TopicPaneSource {
    public let paneID: String
    public let window: TmuxWindow
}

struct TopicPanePlan {
    public let edit: TopicEdit

    public init(source: TopicPaneSource, project homeProject: Project? = nil, title: String = "",
         records: [TopicRecord], windows: [TmuxWindow], projects: [Project],
         id: String = UUID().uuidString.lowercased(), now: Date = Date(), clientTTY: String? = nil) throws {
        let window = source.window
        guard window.paneCount > 0, windows.contains(where: { $0.id == window.id && $0.sessionID == window.sessionID }),
              source.paneID.hasPrefix("%") else { throw TopicEditFailure.sourceUnavailable }
        let directory = TopicEditProjects.path(window.sessionPath)
        let record = records.first { $0.id == window.topicID } ?? records.first { record in
            record.sessions.contains { session in
                guard let worktree = session["worktree_path"]?.string else { return false }
                let path = TopicEditProjects.path(worktree)
                return directory == path || directory.hasPrefix(path + "/")
            }
        }
        let project = homeProject ?? TopicLocation(of: window, record: record, projects: projects).project
        try TopicEditProjects.validate(project)
        let topic = TopicPlan(title: title.trimmingCharacters(in: .whitespacesAndNewlines), project: project, records: records,
                              sessionNames: Set(windows.map(\.sessionName)), id: id, now: now)
        let target = "=" + topic.sessionName + ":"
        var commands: [TopicPlan.Command] = [
            .newTopicSession(name: topic.sessionName, directory: project.path),
            .tmux(["set-option", "-t", target, "@muxify_topic", topic.record.id]),
        ]
        if let clientTTY { commands.append(.tmux(["switch-client", "-c", clientTTY, "-t", target])) }
        if window.paneCount == 1 {
            commands.append(.tmux(["move-window", "-d", "-s", window.sessionID + ":" + window.id, "-t", target]))
        } else {
            commands.append(.tmux(["break-pane", "-d", "-s", source.paneID, "-t", target]))
        }
        commands.append(.removeTopicPlaceholder)
        edit = TopicEdit(record: topic.record, commands: commands, selection: .paneID(source.paneID))
    }
}
