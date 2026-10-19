import Foundation

/// What the user picks in the New Topic and Add Project lists: a Project, and the
/// Worktree of it when the Project is a repository. A plain directory has no Worktree.
public struct ProjectChoice: Identifiable, Equatable, Sendable {
    public let project: Project
    public let worktree: Worktree?

    public init(project: Project, worktree: Worktree?) {
        self.project = project
        self.worktree = worktree
    }

    public var id: String { directory.real }
    public var directory: Folder { worktree?.folder ?? project.folder }
    /// Names the Session this row opens.
    public var name: String { worktree.map { project.name(ofWorktreeAt: $0.folder) } ?? project.name }
    public var displayName: String { worktree.map { project.displayName(ofWorktreeAt: $0.folder) } ?? project.displayName }
    /// A checkout in its own folder, not the Project folder itself.
    public var isWorktree: Bool { directory != project.folder }

    /// `newWorktree` asks for a new Worktree from this row's Worktree, at its HEAD or at the ref `base`; a plain
    /// directory has none to start from.
    public func workingCopy(newWorktree: Bool, base: String? = nil) -> TopicWorkingCopyChoice {
        guard let worktree else { return .project }
        return newWorktree ? .newWorktree(from: worktree.folder.path, base: base) : .worktree(path: worktree.folder.path)
    }

    public static func choices(of project: Project) -> [ProjectChoice] {
        let worktrees = project.layout.worktrees
        guard !worktrees.isEmpty else { return [ProjectChoice(project: project, worktree: nil)] }
        return worktrees.map { ProjectChoice(project: project, worktree: $0) }
    }

    /// The row whose directory holds `folder`, nearest first, so a Worktree inside a bare
    /// Project folder wins over the folder.
    public static func containing(_ folder: Folder, in projects: [Project]) -> ProjectChoice? {
        projects.flatMap(choices).filter { $0.directory.contains(folder) }.max { $0.directory.real.count < $1.directory.real.count }
    }
}

/// One row of the New Topic and Add Project lists.
public struct ProjectRow: Identifiable, Equatable, Sendable {
    public let choice: ProjectChoice
    /// The other open Topics whose live Sessions use this row's folder, by label. The row can still be picked:
    /// each Topic gets its own Session there.
    public let alsoIn: [TopicSummary]

    public init(choice: ProjectChoice, alsoIn: [TopicSummary]) {
        self.choice = choice
        self.alsoIn = alsoIn
    }

    public var id: String { choice.id }
    public var note: String? { alsoIn.isEmpty ? nil : "Also in " + alsoIn.map(\.label).joined(separator: ", ") }
}

/// Which folders the open Topics' live Sessions use.
public struct WorktreeOccupancy {
    /// A directory to the other open Topics whose Sessions use it.
    public let alsoIn: [Folder: [TopicSummary]]
    /// The Project folders the Topic `addingTo` already has a Session in; it cannot add them again.
    public let occupied: Set<Folder>

    /// `titles` maps an open Topic's id to the label the host shows for it, such as the Sidebar title.
    /// A Topic without one gets its `topic list` label.
    public init(windows: [TmuxWindow], records: [TopicRecord], projects: [Project], titles: [String: String], addingTo topic: TopicRecord? = nil) {
        let open = Dictionary(records.filter { $0.settledAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var alsoIn: [Folder: Set<TopicSummary>] = [:]
        var occupied: Set<Folder> = []
        for window in windows {
            guard let id = window.topicID, let record = open[id] else { continue }
            let location = TopicLocation(of: window, record: record, projects: projects)
            if id == topic?.id {
                occupied.insert(location.project.folder)
            } else {
                // A Session with no Worktree lives in the Project folder, which is the main checkout of a plain repository.
                let folder = location.worktree ?? location.project.folder
                let summary = titles[id].map { TopicSummary(id: id, label: $0, tags: record.tags.sorted()) } ?? TopicSummary(record: record)
                alsoIn[folder, default: []].insert(summary)
            }
        }
        self.alsoIn = alsoIn.mapValues { $0.sorted { ($0.label, $0.id) < ($1.label, $1.id) } }
        self.occupied = occupied
    }

    public func alsoIn(_ choice: ProjectChoice) -> [TopicSummary] {
        alsoIn[choice.directory] ?? []
    }
}

public enum ProjectRows {
    /// The rows of the New Topic list, or of the Add Project list of `topic`, in Config order.
    public static func build(projects: [Project], windows: [TmuxWindow], records: [TopicRecord], titles: [String: String],
                             addingTo topic: TopicRecord? = nil) -> [ProjectRow] {
        let occupancy = WorktreeOccupancy(windows: windows, records: records, projects: projects, titles: titles, addingTo: topic)
        return projects.filter { !occupancy.occupied.contains($0.folder) }.flatMap(ProjectChoice.choices).map { choice in
            ProjectRow(choice: choice, alsoIn: occupancy.alsoIn(choice))
        }
    }
}
