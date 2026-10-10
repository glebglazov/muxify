import Foundation

/// One checkout of a Project's repository, as `git worktree list` reports it.
public struct Worktree: Hashable, Sendable {
    public let path: String
    /// Nil when HEAD is detached.
    public let branch: String?

    public var folder: String { (path as NSString).lastPathComponent }
}

/// What git says a Project directory is. Read with `detect`, never from folder names.
public enum ProjectLayout: Equatable, Sendable {
    case directory
    case plainRepository([Worktree])
    case bareRepository([Worktree])

    public var worktrees: [Worktree] {
        switch self {
        case .directory: return []
        case .plainRepository(let worktrees), .bareRepository(let worktrees): return worktrees
        }
    }

    /// What `ProjectDiscovery` finds at `path` alone. A folder inside somebody else's checkout is a plain
    /// directory, so a Project that is a subfolder of a repository does not list that repository's Worktrees.
    public static func detect(at path: String) -> ProjectLayout {
        ProjectDiscovery.discover([ProjectRoot(path: path)], aliases: [:]).first?.layout ?? .directory
    }

    /// The layout the discovery script reports. git lists real paths; a Worktree under the Project's
    /// real folder is given under `path`, so it matches what the Config wrote, symlinks included.
    init(kind: String, worktreeList: String, path: String, realPath: String) {
        let root = Self.resolved(realPath)
        let worktrees = Self.parse(worktreeList: worktreeList).map { worktree in
            let real = Self.resolved(worktree.path)
            guard real == root || real.hasPrefix(root + "/") else { return worktree }
            return Worktree(path: Self.standardized(path) + real.dropFirst(root.count), branch: worktree.branch)
        }
        switch kind {
        case "bare": self = .bareRepository(worktrees)
        case "plain": self = .plainRepository(worktrees)
        default: self = .directory
        }
    }

    /// The checkouts in `git worktree list --porcelain`, without the bare entry and
    /// without prunable entries whose folder is gone.
    public static func parse(worktreeList: String) -> [Worktree] {
        worktreeList.components(separatedBy: "\n\n").compactMap { block -> Worktree? in
            let lines = block.components(separatedBy: "\n")
            guard let path = lines.first(where: { $0.hasPrefix("worktree ") })?.dropFirst(9), !path.isEmpty,
                  !lines.contains("bare"), !lines.contains(where: { $0.hasPrefix("prunable") }) else { return nil }
            let branch = lines.first { $0.hasPrefix("branch refs/heads/") }.map { String($0.dropFirst(18)) }
            return Worktree(path: standardized(String(path)), branch: branch)
        }
    }

    /// git reports real paths (`/private/tmp`), the Config reports what the user wrote.
    private static func standardized(_ path: String) -> String { (path as NSString).standardizingPath }

    /// git resolves symlinks, so a Config path through a symlinked folder matches git's only once resolved too.
    private static func resolved(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
}
