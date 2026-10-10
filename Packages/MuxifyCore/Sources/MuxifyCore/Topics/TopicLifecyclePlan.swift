import Foundation

public struct TopicSettleSession: Identifiable, Codable, Hashable, Sendable {
    /// Raw values are the Settle sheet's titles; the wire uses `kill` and `keep`.
    public enum Disposition: String, CaseIterable, Codable, Sendable {
        case kill = "Kill"
        case keep = "Keep with no Topic"

        public init(from decoder: Decoder) throws {
            switch try decoder.singleValueContainer().decode(String.self) {
            case "kill": self = .kill
            case "keep": self = .keep
            case let value: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown disposition \(value)"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            try value.encode(self == .kill ? "kill" : "keep")
        }
    }

    public let id: String
    public let name: String
    public var disposition: Disposition
    public let worktree: TopicPlan.WorktreeSpec?
    public var removeWorktree = false
    public var reviewedWindows: [String: [String]]? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, disposition, worktree
        case reviewedWindows = "reviewed_windows"
        case removeWorktree = "remove_worktree"
    }

    public static func choices(topic: TopicRecord, snapshot: TmuxSnapshot, projects: [Project],
                        mergedWorktrees: Set<String> = []) -> [TopicSettleSession] {
        var seen: Set<String> = []
        return snapshot.windows.filter { $0.topicID == topic.id && seen.insert($0.sessionID).inserted }.map { window in
            let location = TopicLocation(of: window, record: topic, projects: projects)
            let working = snapshot.agents.contains { $0.sessionID == window.sessionID && $0.status == .working }
            let remembered = topic.sessions.first { $0["project_path"]?.string == location.project.path }
            let worktree = location.worktreePath.flatMap { path -> TopicPlan.WorktreeSpec? in
                guard mergedWorktrees.contains(path), let branch = remembered?["branch"]?.string else { return nil }
                return .init(projectPath: location.project.path, path: path, branch: branch)
            }
            return Self(id: window.sessionID, name: window.sessionName, disposition: working ? .keep : .kill,
                        worktree: worktree, reviewedWindows: windows(in: window.sessionID, snapshot: snapshot))
        }
    }

    static func windows(in sessionID: String, snapshot: TmuxSnapshot) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: snapshot.windows.filter { $0.sessionID == sessionID }.map { window in
            (window.id, snapshot.panes.filter { $0.windowID == window.id }.map(\.id).sorted())
        })
    }
}

struct TopicSettlePlan {
    public let edit: TopicEdit

    public init(topic: TopicRecord, snapshot: TmuxSnapshot, projects: [Project], choices: [TopicSettleSession],
         outcome: String, mergedWorktrees: Set<String> = [], now: Date = Date(), order: SessionOrder = .oldestFirst) {
        var record = topic.remembering(snapshot, projects: projects, order: order) ?? topic
        record.settledAt = ISO8601DateFormatter().string(from: now)
        record.outcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        record.snoozedUntil = nil
        let defaults = TopicSettleSession.choices(topic: record, snapshot: snapshot, projects: projects,
                                                 mergedWorktrees: mergedWorktrees)
        var commands: [TopicPlan.Command] = []
        for session in defaults {
            let choice = choices.first { $0.id == session.id } ?? session
            switch choice.disposition {
            case .kill: commands.append(.tmux(["kill-session", "-t", session.id]))
            case .keep: commands.append(.tmux(["set-option", "-u", "-t", session.id, "@muxify_topic"]))
            }
        }
        for session in defaults {
            guard let choice = choices.first(where: { $0.id == session.id }), choice.disposition == .kill,
                  choice.removeWorktree, let worktree = session.worktree else { continue }
            let keptWindows = snapshot.windows.filter { window in
                let member = defaults.first { $0.id == window.sessionID }
                let disposition = member.flatMap { member in choices.first { $0.id == member.id }?.disposition ?? member.disposition }
                return member == nil || disposition == .keep
            }
            guard !keptWindows.contains(where: { $0.path == worktree.path || $0.path.hasPrefix(worktree.path + "/")
                || $0.sessionPath == worktree.path || $0.sessionPath.hasPrefix(worktree.path + "/") }) else { continue }
            commands.append(.removeMergedWorktree(worktree))
        }
        edit = TopicEdit(record: record, commands: commands, selection: .unchanged)
    }
}

/// What Reopen or Start Fresh creates for a Dormant or Settled Topic. The app shows it before the user
/// chooses, and `TopicReopenPlan` turns the same value into tmux commands, so the two cannot disagree.
public struct TopicReopening: Hashable {
    public enum Choice: Hashable, Sendable {
        /// The remembered Windows, their Tabs and their Agents.
        case reopen
        /// One shell Window in each remembered Session.
        case startFresh
    }

    public struct Session: Hashable {
        public let projectPath: String
        public let projectName: String
        public let name: String
        public let directory: String
        public let branch: String?
        /// The Worktree at `directory` is gone, so it is created again on `branch`.
        public let createsWorktree: Bool
        /// The commit where the Topic's branch started. When `branch` is gone too, the new branch starts here.
        public let base: String?
        public let windows: [Window]
    }

    public struct Window: Hashable {
        public let name: String
        public let directory: String
        public let browser: StoredBrowser
        public let agent: AgentResume?
    }

    public struct AgentResume: Hashable {
        public let kind: AgentKind
        public let conversation: String
    }

    /// Nil when the Topic remembers no Session and has no Home Project, so nothing is created.
    public let slug: String?
    public let sessions: [Session]

    public init(topic: TopicRecord, records: [TopicRecord], windows: [TmuxWindow], projects: [Project],
                existingDirectories: Set<String>, choice: Choice) throws {
        let remembered = topic.sessions.isEmpty ? topic.homeProject.map { [.object(["project_path": JSONValue.string($0)])] } ?? [] : topic.sessions
        let locations = try remembered.map { session -> Project in
            guard let path = session["project_path"]?.string, !path.isEmpty else { throw TopicEditFailure.invalidProject }
            let project = Project.containing(path, in: projects) ?? Project(path: path, name: (path as NSString).lastPathComponent)
            guard !project.name.isEmpty, !project.name.contains(":"), !project.name.contains("."),
                  project.name.rangeOfCharacter(from: .controlCharacters) == nil else { throw TopicEditFailure.invalidProject }
            return project
        }
        guard let home = locations.first else {
            slug = nil
            sessions = []
            return
        }
        guard Set(locations.map(\.path)).count == locations.count else { throw TopicEditFailure.duplicateProject }
        guard Set(locations.map(\.name)).count == locations.count else { throw TopicEditFailure.sessionNameInUse }
        let slug = TopicNaming.slug(title: topic.title ?? "", project: home, records: records,
                                    sessionNames: Set(windows.map(\.sessionName)), excludingTopicID: topic.id,
                                    projectNames: Set(locations.map(\.name)))
        self.slug = slug
        sessions = try zip(remembered, locations).map { session, project in
            let directory = session["worktree_path"]?.string ?? project.path
            let createsWorktree = session["worktree_path"]?.string.map { !existingDirectories.contains($0) } ?? false
            let branch = session["branch"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            if createsWorktree, branch == nil { throw TopicEditFailure.invalidProject }
            let saved = session["windows"]?.array ?? []
            let windows = choice == .startFresh || saved.isEmpty
                ? [Window(name: "shell", directory: directory, browser: StoredBrowser(), agent: nil)]
                : saved.map { Self.window($0, directory: directory) }
            return Session(projectPath: project.path, projectName: project.name, name: project.name + "/" + slug, directory: directory, branch: branch,
                           createsWorktree: createsWorktree, base: session[TopicWorktrees.baseKey]?.string, windows: windows)
        }
    }

    /// The remembered Worktrees that are still on disk, which Reopen uses as they are.
    public static func existingWorktrees(of topic: TopicRecord) -> Set<String> {
        Set(topic.sessions.compactMap { $0["worktree_path"]?.string }.filter { FileManager.default.fileExists(atPath: $0) })
    }

    private static func window(_ window: JSONValue, directory: String) -> Window {
        let tabs = window["browser_tabs"]?.array?.compactMap(\.string) ?? []
        let active: Int
        if case .integer(let value)? = window["browser_active_tab"] { active = Int(value) } else { active = 0 }
        let browserOpen: Bool
        if case .bool(let value)? = window["browser_open"] { browserOpen = value } else { browserOpen = !tabs.isEmpty }
        let terminalOpen: Bool
        if case .bool(let value)? = window["terminal_open"] { terminalOpen = value } else { terminalOpen = true }
        let shown: PanelLayout.Shown = !browserOpen ? .terminal : terminalOpen ? .both : .browser
        let agent = window["agent"]?.string.flatMap(AgentKind.init(rawValue:)).flatMap { kind -> AgentResume? in
            guard let conversation = window["agent_conversation"]?.string, !conversation.isEmpty else { return nil }
            return AgentResume(kind: kind, conversation: conversation)
        }
        return Window(name: window["name"]?.string ?? "shell", directory: window["directory"]?.string ?? directory,
                      browser: StoredBrowser(tabURLs: tabs, activeTab: active, layout: PanelLayout(shown: shown)), agent: agent)
    }
}

struct TopicReopenPlan {
    public let edit: TopicEdit

    public init(topic: TopicRecord, records: [TopicRecord], windows: [TmuxWindow], projects: [Project],
         existingDirectories: Set<String>, choice: TopicReopening.Choice = .reopen) throws {
        guard !windows.contains(where: { $0.topicID == topic.id }) else { throw TopicEditFailure.destinationUnavailable }
        let reopening = try TopicReopening(topic: topic, records: records, windows: windows, projects: projects,
                                           existingDirectories: existingDirectories, choice: choice)
        guard let slug = reopening.slug, let home = reopening.sessions.first else {
            // Nothing to create. A Settled Topic goes back to the top of its part of the Topics list; an open one stays where it is.
            var reopened: TopicRecord?
            if topic.settledAt != nil {
                var record = topic
                record.slug = TopicNaming.slug(title: topic.title ?? "", project: nil, records: records, sessionNames: [],
                                               excludingTopicID: topic.id)
                record.settledAt = nil
                record.snoozedUntil = nil
                record.order = TopicOrder.firstOrder(in: records, pinned: topic.isPinned)
                reopened = record
            }
            edit = TopicEdit(record: nil, commands: [], selection: .emptyTopic(topic.id), completion: reopened.map(TopicEdit.Completion.save))
            return
        }
        var commands: [TopicPlan.Command] = []
        for session in reopening.sessions {
            if session.createsWorktree, let branch = session.branch {
                commands.append(.restoreWorktree(.init(projectPath: session.projectPath, path: session.directory, branch: branch),
                                                 base: session.base))
            }
            let target = "=" + session.name + ":"
            let windowTarget = target + "$"
            for (index, window) in session.windows.enumerated() {
                if index == 0 {
                    commands.append(.reopenSession(name: session.name, directory: session.directory, windowName: window.name))
                    commands.append(.tmux(["set-option", "-t", target, "@muxify_topic", topic.id]))
                    if window.directory != session.directory {
                        commands.append(.tmux(["respawn-window", "-k", "-t", windowTarget, "-c", window.directory]))
                    }
                } else {
                    commands.append(.tmux(["new-window", "-d", "-a", "-t", windowTarget, "-c", window.directory, "-n", window.name]))
                }
                commands.append(.tmux(window.browser.setOptionArgs(windowID: windowTarget)))
                if let agent = window.agent {
                    commands.append(.sendKeys(target: windowTarget, keys: [agent.kind.resumeCommand(conversation: agent.conversation)], literal: true))
                    commands.append(.sendKeys(target: windowTarget, keys: ["Enter"], literal: false))
                }
            }
        }
        var reopened = topic
        reopened.slug = slug
        reopened.settledAt = nil
        reopened.order = TopicOrder.firstOrder(in: records, pinned: topic.isPinned)
        edit = TopicEdit(record: topic, commands: commands, selection: .sessionName(home.name), completion: .save(reopened))
    }
}

extension AgentKind {
    public func resumeCommand(conversation: String) -> String {
        let argument = "'" + conversation.replacingOccurrences(of: "'", with: "'\\''") + "'"
        switch self {
        case .claude: return "claude --resume " + argument
        case .codex: return "codex resume " + argument
        case .opencode: return "opencode --session " + argument
        case .pi: return "pi --session " + argument
        }
    }
}
