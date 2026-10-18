import Foundation

public struct TopicForgetChoices: Sendable {
    public struct Worktree: Identifiable, Sendable {
        public var id: String { spec.path }
        public let spec: TopicPlan.WorktreeSpec
        public let isClean: Bool
        public let sessionIDs: Set<String>

        public func canRemove(sessions: [TopicSettleSession]) -> Bool {
            isClean && sessionIDs.isSubset(of: Set(sessions.filter { $0.disposition == .kill }.map(\.id)))
        }
    }

    public var sessions: [TopicSettleSession]
    public let worktrees: [Worktree]

    init(topic: TopicRecord, snapshot: TmuxSnapshot, projects: [Project], root: String) {
        let record = topic.remembering(snapshot, projects: projects, order: .oldestFirst) ?? topic
        sessions = TopicSettleSession.choices(topic: record, snapshot: snapshot, projects: projects)
        let root = Folder.local(root)
        let windows = snapshot.windows.map { (sessionID: $0.sessionID, folders: $0.folders) }
        var seen: Set<Folder> = []
        worktrees = (topic.sessions + record.sessions).compactMap { session in
            guard TopicWorktrees.isCreated(session), let project = session["project_path"]?.string,
                  let path = session["worktree_path"]?.string, let branch = session["branch"]?.string else { return nil }
            let folder = Folder.local(path)
            guard TopicWorktrees.isInside(folder, root: root), FileManager.default.fileExists(atPath: path),
                  seen.insert(folder).inserted else { return nil }
            let status = try? Shell.run("/usr/bin/git", ["status", "--porcelain", "--untracked-files=normal"], directory: path)
            return Worktree(spec: .init(projectPath: project, path: path, branch: branch),
                            isClean: status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
                            sessionIDs: Set(windows.filter { $0.folders.contains(where: folder.contains) }.map(\.sessionID)))
        }
    }
}

struct TopicForgetPlan {
    let edit: TopicEdit

    init(topic: TopicRecord, snapshot: TmuxSnapshot, projects: [Project], choices: [TopicSettleSession],
         worktrees: [String], root: String) {
        let available = TopicForgetChoices(topic: topic, snapshot: snapshot, projects: projects, root: root)
        let sessions = available.sessions.map { session -> TopicSettleSession in
            var result = session
            result.disposition = choices.first { $0.id == session.id }?.disposition ?? session.disposition
            return result
        }
        var commands = sessions.flatMap { session -> [TopicPlan.Command] in
            switch session.disposition {
            case .kill: return [.tmux(["kill-session", "-t", session.id])]
            case .keep: return [.tmux(["set-option", "-u", "-t", session.id, "@muxify_topic"]), .tmux(SessionLock.unsetOption(session.id))]
            }
        }
        for tree in available.worktrees where tree.canRemove(sessions: sessions) && worktrees.contains(tree.id) {
            commands.append(.removeCleanWorktree(tree.spec))
        }
        edit = TopicEdit(record: nil, commands: commands, selection: .unchanged, completion: .forget(topic.id))
    }
}
