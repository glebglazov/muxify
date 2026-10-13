import Foundation

enum TopicNaming {
    public static func slugify(_ title: String) -> String {
        let ascii = title.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let words = ascii.components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }
        var slug = ""
        for word in words {
            let candidate = slug.isEmpty ? word : slug + "-" + word
            if candidate.count > 28 {
                if slug.isEmpty { slug = String(word.prefix(28)) }
                break
            }
            slug = candidate
        }
        return slug.isEmpty ? "topic" : slug
    }

    /// `project` is nil for a Topic with no Session yet; its first Session checks the name when it opens.
    public static func slug(title: String, project: Project?, records: [TopicRecord], sessionNames: Set<String>,
                     excludingTopicID: String? = nil, projectNames: Set<String> = []) -> String {
        let used = Set(records.filter { $0.settledAt == nil && $0.id != excludingTopicID }.compactMap(\.slug))
        let names = projectNames.union(project.map { [$0.name] } ?? [])
        func available(_ slug: String) -> Bool {
            !used.contains(slug) && names.allSatisfy { !sessionNames.contains($0 + "/" + slug) }
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var number = 1
            while !available("untitled-\(number)") { number += 1 }
            return "untitled-\(number)"
        }
        let base = slugify(title)
        var slug = base
        var number = 2
        while !available(slug) { slug = "\(base)-\(number)"; number += 1 }
        return slug
    }
}

/// Where a Topic's first Session opens.
enum TopicWorkingCopy: Equatable {
    /// The Project folder of a plain directory.
    case homeProject
    /// A Worktree the user picked in the Project list.
    case worktree(Worktree)
    /// A Worktree the Topic creates on the branch `<slug>` at `commit`, in `root/<project name>/<slug>` for a bare
    /// and a plain repository alike.
    case newWorktree(at: String, root: String)
}

extension TopicWorkingCopy {
    public struct SessionStart {
        public let directory: String
        /// The remembered-Session fields that name the Worktree; empty for the Project folder.
        public let worktreeFields: [String: JSONValue]
        public let newWorktree: TopicPlan.NewWorktree?
    }

    /// `slug` names the branch and folder of a new Worktree.
    public func sessionStart(in project: Project, slug: String) -> SessionStart {
        switch self {
        case .homeProject:
            return SessionStart(directory: project.path, worktreeFields: [:], newWorktree: nil)
        case .worktree(let worktree):
            var fields: [String: JSONValue] = ["worktree_path": .string(worktree.path), TopicWorktrees.createdKey: .bool(false)]
            fields["branch"] = worktree.branch.map(JSONValue.string)
            return SessionStart(directory: worktree.path, worktreeFields: fields, newWorktree: nil)
        case .newWorktree(let commit, let root):
            let path = URL(fileURLWithPath: root).appendingPathComponent(project.name).appendingPathComponent(slug).standardizedFileURL.path
            let worktree = TopicPlan.WorktreeSpec(projectPath: project.path, path: path, branch: slug)
            return SessionStart(directory: worktree.path,
                                worktreeFields: ["worktree_path": .string(worktree.path), "branch": .string(worktree.branch),
                                                 TopicWorktrees.createdKey: .bool(true), TopicWorktrees.baseKey: .string(commit)],
                                newWorktree: TopicPlan.NewWorktree(worktree: worktree, commit: commit))
        }
    }
}

public struct TopicPlan: Sendable {
    public struct WorktreeSpec: Codable, Hashable, Sendable {
        public let projectPath: String
        public let path: String
        public let branch: String

        private enum CodingKeys: String, CodingKey {
            case path, branch
            case projectPath = "project_path"
        }

        public var arguments: [String] { ["worktree", "add", "-b", branch, path] }
    }

    /// A Worktree that git makes before Muxify saves the record and runs `commands`, so a git
    /// failure leaves no Topic and no recorded Session behind.
    public struct NewWorktree: Equatable, Sendable {
        public let worktree: WorktreeSpec
        /// The full id of the commit the branch starts at.
        public let commit: String
    }

    public enum Command: Equatable, Sendable {
        /// `base` is the commit that the remembered Session records. A branch that is gone starts again there.
        case restoreWorktree(WorktreeSpec, base: String?)
        case removeMergedWorktree(WorktreeSpec)
        case removeCleanWorktree(WorktreeSpec)
        case reopenSession(name: String, directory: String, windowName: String)
        case tmux([String])
        /// Keys typed into the target's pane, `literal` as text rather than key names.
        case sendKeys(target: String, keys: [String], literal: Bool)
        case newTopicSession(name: String, directory: String)
        case removeTopicPlaceholder
    }

    public let record: TopicRecord
    public let sessionName: String
    public let commands: [Command]

    init(title: String, project: Project, records: [TopicRecord], sessionNames: Set<String>,
         id: String = UUID().uuidString.lowercased(), now: Date = Date(), clientTTY: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = TopicNaming.slug(title: title, project: project, records: records, sessionNames: sessionNames)
        sessionName = project.name + "/" + slug
        var record = TopicRecord(newTopic: id, title: title, slug: slug, records: records, now: now)
        record.homeProject = project.path
        record.sessions = [.object(["project_path": .string(project.path)])]
        self.record = record
        let target = "=" + sessionName + ":"
        var commands: [Command] = [
            .tmux(["new-session", "-d", "-s", sessionName, "-c", project.path]),
            .tmux(["set-option", "-t", target, "@muxify_topic", id]),
        ]
        if let clientTTY { commands.append(.tmux(["switch-client", "-c", clientTTY, "-t", target])) }
        self.commands = commands
    }
}

extension TopicRecord {
    /// An open Topic, first among the Topics that are not Pinned, with no Session and no Home Project yet.
    public init(newTopic id: String, title: String, slug: String, records: [TopicRecord], now: Date) {
        self.init(id: id, title: title.isEmpty ? nil : title, slug: slug)
        createdAt = ISO8601DateFormatter().string(from: now)
        order = TopicOrder.firstOrder(in: records.map(TopicListEntry.topic), pinned: false)
    }
}
