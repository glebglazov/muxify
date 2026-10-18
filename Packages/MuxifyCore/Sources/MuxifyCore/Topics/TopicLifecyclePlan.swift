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
                        mergedWorktrees: Set<Folder> = []) -> [TopicSettleSession] {
        var seen: Set<String> = []
        let byProject = topic.rememberedSessions(by: "project_path")
        return snapshot.windows.filter { $0.topicID == topic.id && seen.insert($0.sessionID).inserted }.map { window in
            let location = TopicLocation(of: window, record: topic, projects: projects)
            let working = snapshot.agents.contains { $0.sessionID == window.sessionID && $0.status == .working }
            let remembered = byProject[location.project.folder]
            let worktree = location.worktree.flatMap { folder -> TopicPlan.WorktreeSpec? in
                guard mergedWorktrees.contains(folder), let branch = remembered?["branch"]?.string else { return nil }
                return .init(projectPath: location.project.folder.path, path: folder.path, branch: branch)
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
         outcome: String, mergedWorktrees: Set<Folder> = [], now: Date = Date(), order: SessionOrder = .oldestFirst) {
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
            case .keep:
                commands.append(.tmux(["set-option", "-u", "-t", session.id, "@muxify_topic"]))
                commands.append(.tmux(SessionLock.unsetOption(session.id)))
            }
        }
        let windows = snapshot.windows.map { (sessionID: $0.sessionID, folders: $0.folders) }
        for session in defaults {
            guard let choice = choices.first(where: { $0.id == session.id }), choice.disposition == .kill,
                  choice.removeWorktree, let worktree = session.worktree else { continue }
            let keptWindows = windows.filter { window in
                let member = defaults.first { $0.id == window.sessionID }
                let disposition = member.flatMap { member in choices.first { $0.id == member.id }?.disposition ?? member.disposition }
                return member == nil || disposition == .keep
            }
            let folder = Folder.local(worktree.path)
            guard !keptWindows.contains(where: { $0.folders.contains(where: folder.contains) }) else { continue }
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
        /// tmux `#{window_layout}`, nil for a Window with one Pane or a record from before Panes were remembered.
        public let layout: String?
        /// In tmux order, at least one.
        public let panes: [Pane]

        public var agents: [AgentResume] {
            panes.compactMap { if case .agent(let agent) = $0.start { return agent }; return nil }
        }
    }

    public struct Pane: Hashable {
        public enum Start: Hashable {
            case shell
            /// The Agent's resume command runs.
            case agent(AgentResume)
            /// The program's command line is typed at the shell's prompt, and the user presses ↩ to run it.
            case typed(String)
        }

        public let directory: String
        public let isActive: Bool
        public let start: Start
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
            let folder = Folder.local(path)
            let project = Project.containing(folder, in: projects) ?? Project(folder: folder, name: (folder.path as NSString).lastPathComponent)
            guard !project.name.isEmpty, !project.name.contains(":"), !project.name.contains("."),
                  project.name.rangeOfCharacter(from: .controlCharacters) == nil else { throw TopicEditFailure.invalidProject }
            return project
        }
        guard let home = locations.first else {
            slug = nil
            sessions = []
            return
        }
        guard Set(locations.map(\.folder)).count == locations.count else { throw TopicEditFailure.duplicateProject }
        guard Set(locations.map(\.name)).count == locations.count else { throw TopicEditFailure.sessionNameInUse }
        let slug = TopicNaming.slug(title: topic.title ?? "", project: home, records: records,
                                    sessionNames: Set(windows.map(\.sessionName)), excludingTopicID: topic.id,
                                    projectNames: Set(locations.map(\.name)))
        self.slug = slug
        sessions = try zip(remembered, locations).map { session, project in
            let directory = session["worktree_path"]?.string ?? project.folder.path
            let createsWorktree = session["worktree_path"]?.string.map { !existingDirectories.contains($0) } ?? false
            let branch = session["branch"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            if createsWorktree, branch == nil { throw TopicEditFailure.invalidProject }
            let saved = session["windows"]?.array ?? []
            let windows = choice == .startFresh || saved.isEmpty
                ? [Window(name: "shell", directory: directory, browser: StoredBrowser(), layout: nil,
                          panes: [Pane(directory: directory, isActive: true, start: .shell)])]
                : saved.map { Self.window($0, directory: directory) }
            return Session(projectPath: project.folder.path, projectName: project.name, name: project.name + "/" + slug, directory: directory, branch: branch,
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
        let windowDirectory = window["directory"]?.string ?? directory
        // A record from before Panes were remembered has one Pane, with the Window's folder and Agent.
        let panes = (window["panes"]?.array).flatMap { $0.isEmpty ? nil : $0.map { Self.pane($0, directory: windowDirectory) } }
            ?? [Pane(directory: windowDirectory, isActive: true, start: agent(window).map(Pane.Start.agent) ?? .shell)]
        let layout = window["layout"]?.string
        return Window(name: window["name"]?.string ?? "shell", directory: windowDirectory,
                      browser: StoredBrowser(tabURLs: tabs, activeTab: active, layout: PanelLayout(shown: shown)),
                      layout: panes.count > 1 && layout?.isEmpty == false ? layout : nil, panes: panes)
    }

    private static func pane(_ pane: JSONValue, directory: String) -> Pane {
        let start: Pane.Start
        if let agent = agent(pane) {
            start = .agent(agent)
        } else if let command = pane["command"]?.string, !command.isEmpty,
                  command.rangeOfCharacter(from: .controlCharacters) == nil {
            start = .typed(command)
        } else {
            start = .shell
        }
        let isActive: Bool
        if case .bool(true)? = pane["active"] { isActive = true } else { isActive = false }
        return Pane(directory: pane["directory"]?.string ?? directory, isActive: isActive, start: start)
    }

    private static func agent(_ fields: JSONValue) -> AgentResume? {
        guard let kind = fields["agent"]?.string.flatMap(AgentKind.init(rawValue:)),
              let conversation = fields["agent_conversation"]?.string, !conversation.isEmpty else { return nil }
        return AgentResume(kind: kind, conversation: conversation)
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
            var reopened: TopicRecord?
            if topic.settledAt != nil {
                var record = topic
                record.slug = TopicNaming.slug(title: topic.title ?? "", project: nil, records: records, sessionNames: [],
                                               excludingTopicID: topic.id)
                record.settledAt = nil
                record.snoozedUntil = nil
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
                let first = window.panes[0].directory
                if index == 0 {
                    commands.append(.reopenSession(name: session.name, directory: session.directory, windowName: window.name))
                    commands.append(.tmux(["set-option", "-t", target, "@muxify_topic", topic.id]))
                    if first != session.directory {
                        commands.append(.tmux(["respawn-window", "-k", "-t", windowTarget, "-c", first]))
                    }
                } else {
                    commands.append(.tmux(["new-window", "-d", "-a", "-t", windowTarget, "-c", first, "-n", window.name]))
                }
                commands.append(.tmux(window.browser.setOptionArgs(windowID: windowTarget)))
                commands += Self.panes(of: window, target: windowTarget)
            }
        }
        var reopened = topic
        reopened.slug = slug
        reopened.settledAt = nil
        edit = TopicEdit(record: topic, commands: commands, selection: .sessionName(home.name), completion: .save(reopened))
    }
}

extension TopicReopenPlan {
    /// The Window's first Pane exists. Each split puts the new Pane last and makes it active, so after the splits a
    /// `.+N` target, N Panes on from the active one with wrap, reaches each Pane whatever `pane-base-index` is. The
    /// layout comes last: a layout from a newer tmux also names its active Pane, and `select-layout` makes it active.
    /// The Window is tiled before each split, so a small detached Window has room for the next Pane.
    static func panes(of window: TopicReopening.Window, target: String) -> [TopicPlan.Command] {
        var commands: [TopicPlan.Command] = []
        for (position, pane) in window.panes.enumerated().dropFirst() {
            if position > 1 { commands.append(.tmux(["select-layout", "-t", target, "tiled"])) }
            commands.append(.tmux(["split-window", "-t", target, "-c", pane.directory]))
        }
        let last = window.panes.count - 1
        let paneTarget = { (position: Int) in position == last ? target : target + ".+" + String(position + 1) }
        for (position, pane) in window.panes.enumerated() {
            switch pane.start {
            case .shell:
                break
            case .agent(let agent):
                commands.append(.sendKeys(target: paneTarget(position),
                                          keys: [agent.kind.resumeCommand(conversation: agent.conversation)], literal: true))
                commands.append(.sendKeys(target: paneTarget(position), keys: ["Enter"], literal: false))
            case .typed(let command):
                commands.append(.sendKeys(target: paneTarget(position), keys: [command], literal: true))
            }
        }
        if let active = window.panes.firstIndex(where: \.isActive), active != last {
            commands.append(.tmux(["select-pane", "-t", paneTarget(active)]))
        }
        if last > 0 { commands.append(.tmux(["select-layout", "-t", target, window.layout ?? "tiled"])) }
        return commands
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
