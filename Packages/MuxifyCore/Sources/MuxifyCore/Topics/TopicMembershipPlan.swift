import Foundation

public struct TopicMembershipPlan: Sendable {
    public enum Source {
        case window(TmuxWindow)
        case pane(PaneID, TmuxWindow)
        case session(TmuxWindow)

        public func resolved(in windows: [TmuxWindow]) throws -> Source {
            switch self {
            case .pane(let id, let previous):
                guard let current = windows.first(where: { $0.id == previous.id }) else { throw Failure.sourceUnavailable }
                return .pane(id, current)
            case .window(let previous):
                guard let current = windows.first(where: { $0.id == previous.id }) else { throw Failure.sourceUnavailable }
                return .window(current)
            case .session(let previous):
                guard let current = windows.first(where: { $0.sessionID == previous.sessionID }) else { throw Failure.sourceUnavailable }
                return .session(current)
            }
        }

        public var window: TmuxWindow {
            switch self {
            case .window(let window), .session(let window), .pane(_, let window): return window
            }
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case occupiedProject, sessionNameInUse, invalidProject, sourceUnavailable, destinationUnavailable

        public var description: String {
            switch self {
            case .destinationUnavailable: return "The destination Topic is no longer open."
            case .sourceUnavailable: return "The source Window or Session is no longer open."
            case .occupiedProject: return "This Topic already has a Session for this Project. Move a Window instead."
            case .sessionNameInUse: return "The Topic's Session name is already in use. Rename that Session first."
            case .invalidProject: return "The Session needs a Project directory with a name that tmux accepts."
            }
        }
    }

    public let record: TopicRecord?
    public let commands: [TopicPlan.Command]
    /// The Session whose Lock the move ends: a Locked Session goes into a Topic (ADR 0018).
    private(set) var endedLockOf: String? = nil
    /// The Topic that the moved Session left, without that Session, when it is not `record`.
    private(set) var leftTopic: TopicRecord? = nil

    /// The Topic forgets the Session at once: a pending write of the remembered Sessions keeps the last live set,
    /// so without this the Topic stays Dormant and Reopen makes the Session again.
    init(removingSession window: TmuxWindow, records: [TopicRecord], projects: [Project]) {
        record = Self.openTopic(of: window, records: records)?.forgetting(window, projects: projects)
        commands = [.tmux(["set-option", "-u", "-t", window.sessionID, "@muxify_topic"])]
    }

    init(source: Source, destination: TopicRecord, records: [TopicRecord], windows: [TmuxWindow], projects: [Project],
         clientTTY: String? = nil, order: SessionOrder = .oldestFirst) throws {
        let window = source.window
        let sourceRecord = Self.sourceRecord(for: window, records: records)
        let location = TopicLocation(of: window, record: sourceRecord, projects: projects)
        let project = location.project
        guard !project.folder.path.isEmpty, !project.name.contains("."), !project.name.contains(":"), !project.name.contains("\n") else {
            throw Failure.invalidProject
        }
        let existing = Self.occupant(of: destination, project: project, windows: windows, projects: projects)
        if existing?.sessionID == window.sessionID {
            self.record = nil
            self.commands = []
            return
        }
        var record = destination
        let sessionName = project.name + "/" + (destination.slug ?? TopicNaming.slugify(destination.title ?? "topic"))
        var commands: [TopicPlan.Command] = []
        switch source {
        case .session:
            guard existing == nil else { throw Failure.occupiedProject }
            guard !windows.contains(where: { $0.sessionID != window.sessionID && $0.sessionName == sessionName }) else {
                throw Failure.sessionNameInUse
            }
            commands = [
                .tmux(["rename-session", "-t", window.sessionID, sessionName]),
                .tmux(["set-option", "-t", window.sessionID, "@muxify_topic", record.id]),
            ]
            if window.lockOrder != nil {
                commands.append(.tmux(SessionLock.unsetOption(window.sessionID)))
                endedLockOf = window.sessionID
            }
            if let clientTTY {
                commands.append(.tmux(["switch-client", "-c", clientTTY, "-t", window.sessionID + ":" + window.id]))
            }
            var remembered: [String: JSONValue] = ["project_path": .string(project.folder.path)]
            if let worktree = location.worktree {
                remembered["worktree_path"] = .string(worktree.path)
                remembered["branch"] = sourceRecord?.rememberedSessions(by: "worktree_path")[worktree]?["branch"]
            }
            record.recordingNewSession(remembered, order: order)
        case .window, .pane:
            let target: String
            if let existing { target = existing.sessionID + ":" }
            else {
                guard !windows.contains(where: { $0.sessionName == sessionName }) else { throw Failure.sessionNameInUse }
                target = "=" + sessionName + ":"
                commands = [
                    .newTopicSession(name: sessionName, directory: project.folder.path),
                    .tmux(["set-option", "-t", target, "@muxify_topic", record.id]),
                ]
                record.recordingNewSession(["project_path": .string(project.folder.path)], order: order)
            }
            if let clientTTY {
                commands.append(.tmux(["switch-client", "-c", clientTTY, "-t", target]))
            }
            if case .pane(let pane, _) = source, window.paneCount > 1 {
                commands.append(.tmux(["break-pane", "-d", "-s", pane.rawValue, "-t", target]))
            } else {
                commands.append(.tmux(["move-window", "-d", "-s", window.sessionID + ":" + window.id, "-t", target]))
            }
            if existing == nil { commands.append(.removeTopicPlaceholder) }
            if let clientTTY, case .window = source {
                commands.append(.tmux(["switch-client", "-c", clientTTY, "-t", target + window.id]))
            }
        }
        if Self.ends(source, windows: windows), let left = Self.openTopic(of: window, records: records)?.forgetting(window, projects: projects) {
            if left.id == record.id { record = record.forgetting(window, projects: projects) ?? record }
            else { leftTopic = left }
        }
        self.record = record
        self.commands = commands
    }

    init(source: Source, title: String, records: [TopicRecord], windows: [TmuxWindow], projects: [Project],
         id: String = UUID().uuidString.lowercased(), now: Date = Date(), clientTTY: String? = nil, order: SessionOrder = .oldestFirst) throws {
        let window = source.window
        let project = Self.project(of: window, records: records, projects: projects)
        let topic = TopicPlan(title: title, project: project, records: records,
                              sessionNames: Set(windows.map(\.sessionName)), id: id, now: now)
        try self.init(source: source, destination: topic.record, records: records, windows: windows,
                      projects: projects, clientTTY: clientTTY, order: order)
    }

    /// The Project a Window's Session belongs to, read through its Topic's record when it has one.
    public static func project(of window: TmuxWindow, records: [TopicRecord], projects: [Project]) -> Project {
        TopicLocation(of: window, record: sourceRecord(for: window, records: records), projects: projects).project
    }

    /// The destination's live Window in `project`, when it already has a Session there. A Session cannot
    /// move into a Topic that has one; the Move form dims such a Topic by this rule.
    public static func occupant(of destination: TopicRecord, project: Project, windows: [TmuxWindow], projects: [Project]) -> TmuxWindow? {
        windows.first {
            $0.topicID == destination.id && TopicLocation(of: $0, record: destination, projects: projects).project.folder == project.folder
        }
    }

    /// Whether moving `source` out leaves its Session with no Window, so that tmux ends the Session.
    static func ends(_ source: Source, windows: [TmuxWindow]) -> Bool {
        let window = source.window
        if case .pane = source, window.paneCount > 1 { return false }
        if case .session = source { return true }
        return !windows.contains { $0.sessionID == window.sessionID && $0.id != window.id }
    }

    static func openTopic(of window: TmuxWindow, records: [TopicRecord]) -> TopicRecord? {
        records.first { $0.id == window.topicID && $0.settledAt == nil }
    }

    /// The record that a Window's Session belongs to: its Topic, else a Topic that remembers its Worktree.
    static func sourceRecord(for window: TmuxWindow, records: [TopicRecord]) -> TopicRecord? {
        if let linked = records.first(where: { $0.id == window.topicID }) { return linked }
        let directory = Folder.local(window.sessionPath)
        return records.first { record in
            record.sessions.contains { session in
                session["worktree_path"]?.string.map { Folder.local($0).contains(directory) } ?? false
            }
        }
    }

}
