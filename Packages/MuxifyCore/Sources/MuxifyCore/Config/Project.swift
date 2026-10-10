import Foundation

public struct Project: Equatable, Identifiable, Sendable {
    public let path: String
    /// Names the Project's tmux Sessions and Topic records, so it never changes with the alias.
    public let name: String
    /// What the user calls the Project in the Config's `projects_aliases`. It may hold spaces, so it is only shown.
    public var alias: String?
    /// What git says the directory is. The Config gives `.directory`; the Workspace fills it in.
    public var layout: ProjectLayout = .directory

    public init(path: String, name: String, alias: String? = nil, layout: ProjectLayout = .directory) {
        self.path = path
        self.name = name
        self.alias = alias
        self.layout = layout
    }

    public var id: String { path }

    /// The name lists and Session labels show: the alias when the Config gives one.
    public var displayName: String { alias ?? name }

    /// The name of a Session in a checkout of this Project. A Worktree in another folder is
    /// `<name>/<folder>`. The Project folder itself, the main checkout of a plain repository, is just `<name>`.
    public func name(ofWorktreeAt worktreePath: String) -> String { checkout(worktreePath, of: name, folder: Self.sessionName) }

    /// A checkout's name in lists and Session labels, by the rule of `name(ofWorktreeAt:)` on the display name.
    public func displayName(ofWorktreeAt worktreePath: String) -> String { checkout(worktreePath, of: displayName) { $0 } }

    private func checkout(_ worktreePath: String, of projectName: String, folder: (String) -> String) -> String {
        let worktree = (worktreePath as NSString).standardizingPath
        guard worktree != (path as NSString).standardizingPath else { return projectName }
        return projectName + "/" + folder((worktree as NSString).lastPathComponent)
    }

    /// A folder name as tmux takes it in a Session name: spaces go, and `.` and `:`, which tmux
    /// refuses, become `_`.
    public static func sessionName(_ folder: String) -> String {
        folder.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    /// The Project at `path`: named as the Config Project that holds it, else after its folder.
    public static func named(at path: String, in projects: [Project]) -> Project {
        let owner = containing(path, in: projects)
        return Project(path: path, name: owner?.name ?? sessionName((path as NSString).lastPathComponent), alias: owner?.alias)
    }

    public static func containing(_ directory: String, in projects: [Project]) -> Project? {
        let path = URL(fileURLWithPath: directory).standardizedFileURL.path
        return projects.filter { path == $0.path || path.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
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
