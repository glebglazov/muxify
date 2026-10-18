import Foundation

public struct Project: Equatable, Identifiable, Sendable {
    public let folder: Folder
    /// Names the Project's tmux Sessions and Topic records, so it never changes with the alias.
    public let name: String
    /// What the user calls the Project in the Config's `projects_aliases`. It may hold spaces, so it is only shown.
    public var alias: String?
    /// What git says the directory is. The Config gives `.directory`; the Workspace fills it in.
    public var layout: ProjectLayout = .directory

    public init(folder: Folder, name: String, alias: String? = nil, layout: ProjectLayout = .directory) {
        self.folder = folder
        self.name = name
        self.alias = alias
        self.layout = layout
    }

    /// A Project in a folder on this Mac.
    public init(path: String, name: String, alias: String? = nil, layout: ProjectLayout = .directory) {
        self.init(folder: .local(path), name: name, alias: alias, layout: layout)
    }

    public var id: String { folder.real }

    /// The name lists and Session labels show: the alias when the Config gives one.
    public var displayName: String { alias ?? name }

    /// The name of a Session in a checkout of this Project. A Worktree in another folder is
    /// `<name>/<folder>`. The Project folder itself, the main checkout of a plain repository, is just `<name>`.
    public func name(ofWorktreeAt worktree: Folder) -> String { checkout(worktree, of: name, folder: Self.sessionName) }

    /// A checkout's name in lists and Session labels, by the rule of `name(ofWorktreeAt:)` on the display name.
    public func displayName(ofWorktreeAt worktree: Folder) -> String { checkout(worktree, of: displayName) { $0 } }

    private func checkout(_ worktree: Folder, of projectName: String, folder rename: (String) -> String) -> String {
        guard worktree != folder else { return projectName }
        return projectName + "/" + rename((worktree.path as NSString).lastPathComponent)
    }

    /// A folder name as tmux takes it in a Session name: spaces go, and `.` and `:`, which tmux
    /// refuses, become `_`.
    public static func sessionName(_ folder: String) -> String {
        folder.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    /// The Project at `folder`: named as the Config Project that holds it, else after its folder.
    public static func named(at folder: Folder, in projects: [Project]) -> Project {
        let owner = containing(folder, in: projects)
        return Project(folder: folder, name: owner?.name ?? sessionName((folder.path as NSString).lastPathComponent), alias: owner?.alias)
    }

    /// The Project whose folder holds `folder`, nearest first.
    public static func containing(_ folder: Folder, in projects: [Project]) -> Project? {
        projects.filter { $0.folder.contains(folder) }.max { $0.folder.real.count < $1.folder.real.count }
    }
}

/// One `projects.paths` entry of the Config: the folders `path` matches, and every folder under each of them
/// down to `depth` levels. It is looked for again each time Muxify lists Projects, so a folder made after the
/// Config loaded is a Project too.
public struct ProjectRoot: Equatable, Sendable {
    /// Absolute, or starting with `~`, the home folder of the machine that looks for it. It may be a glob.
    public let path: String
    /// 0 is each matched folder itself. Hidden folders are skipped.
    public let depth: Int
    /// How many trailing folder names name each Project.
    public let displayDepth: Int

    public init(path: String, depth: Int = 0, displayDepth: Int = 1) {
        self.path = path
        self.depth = depth
        self.displayDepth = displayDepth
    }
}
