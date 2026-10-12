import Foundation

extension TopicRecord {
    /// No live Sessions means Dormant. Keep the last live set for Reopen, in the Topic's order of its Sessions.
    /// Until the user orders them, that is oldest first whatever `order` says, so Reopen creates them in the order
    /// they were created before.
    public func remembering(_ snapshot: TmuxSnapshot, projects: [Project], order: SessionOrder,
                            branches: TopicBranches = TopicBranches()) -> TopicRecord? {
        let windows = snapshot.windows.filter { $0.topicID == id }
        guard settledAt == nil, !windows.isEmpty else { return nil }
        var seen: Set<String> = []
        let sessionIDs = TopicSessionOrder.ordered(windows.filter { seen.insert($0.sessionID).inserted }, record: self,
                                                   order: hasManualSessionOrder ? order : .oldestFirst) {
            TopicSessionKey(of: $0, record: self, projects: projects)
        }.map(\.sessionID)
        let remembered = sessionIDs.compactMap { sessionID -> JSONValue? in
            let members = windows.filter { $0.sessionID == sessionID }
            guard let first = members.first else { return nil }
            let location = TopicLocation(of: first, record: self, projects: projects)
            let previous = sessions.first { $0["project_path"]?.string == location.project.path }
            var session = previous?.object ?? [:]
            session["project_path"] = .string(location.project.path)
            session["worktree_path"] = location.worktreePath.map(JSONValue.string)
            session["branch"] = location.worktreePath.flatMap { branches[$0].map(JSONValue.string) ?? session["branch"] }
            let previousWindows = session["windows"]?.array ?? []
            session["windows"] = .array(members.enumerated().map { index, window in
                let previous = previousWindows.first { $0["window_id"]?.string == window.id }
                    ?? (previousWindows.indices.contains(index) && previousWindows[index]["window_id"] == nil
                        ? previousWindows[index] : nil)
                var fields = previous?.object ?? [:]
                fields["window_id"] = .string(window.id)
                fields["directory"] = .string(window.path)
                fields["name"] = .string(window.name)
                fields["pane_count"] = nil
                fields["start_command"] = .string(window.startCommand)
                fields["browser_tabs"] = .array(window.storedBrowser.tabURLs.map(JSONValue.string))
                fields["browser_active_tab"] = .integer(Int64(window.storedBrowser.activeTab))
                fields["browser_open"] = .bool(window.storedBrowser.layout.shown != .terminal)
                fields["terminal_open"] = .bool(window.storedBrowser.layout.shown != .browser)
                let pane = snapshot.panes.first { $0.id == window.activePaneID && $0.windowID == window.id }
                let agent = pane.flatMap { Agent.runs(in: $0) ? $0 : nil }
                fields["agent"] = agent.map { .string($0.agent) }
                fields["agent_conversation"] = agent.flatMap { $0.agentConversation.isEmpty ? nil : .string($0.agentConversation) }
                let panes = snapshot.panes.filter { $0.windowID == window.id }.sorted { $0.index < $1.index }
                fields["layout"] = panes.isEmpty || window.layout.isEmpty ? nil : .string(window.layout)
                fields["panes"] = panes.isEmpty ? nil : .array(panes.map { Self.remembered($0, in: window, commandLines: snapshot.commandLines) })
                return .object(fields)
            })
            return .object(session)
        }
        guard remembered != sessions else { return nil }
        var updated = self
        updated.sessions = remembered
        return updated
    }

    /// An Agent Pane keeps its conversation, a Pane that runs another program keeps its command line, and a shell
    /// keeps only its folder.
    private static func remembered(_ pane: TmuxPane, in window: TmuxWindow, commandLines: PaneCommandLines) -> JSONValue {
        var fields: [String: JSONValue] = ["index": .integer(Int64(pane.index)), "directory": .string(pane.path.isEmpty ? window.path : pane.path),
                                           "active": .bool(pane.isActive)]
        if Agent.runs(in: pane) {
            fields["agent"] = .string(pane.agent)
            if !pane.agentConversation.isEmpty { fields["agent_conversation"] = .string(pane.agentConversation) }
        } else if let line = commandLines[pane] {
            fields["command"] = .string(line)
        }
        return .object(fields)
    }
}

private extension JSONValue {
    var object: [String: JSONValue]? {
        if case .object(let fields) = self { return fields }
        return nil
    }
}
