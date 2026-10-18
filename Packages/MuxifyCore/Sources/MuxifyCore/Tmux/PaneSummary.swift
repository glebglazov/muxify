import Foundation

/// A Pane as the command line tool reports it: where it is, what runs in it, and its Agent. `topic show` and
/// `agent list` both build it from one snapshot, so they agree on what counts as an Agent.
public struct PaneSummary: Codable, Hashable, Sendable {
    /// The Agent in the Pane, from the options its Extension writes and the Unread mark that Muxify writes.
    public struct AgentState: Codable, Hashable, Sendable {
        public var kind: AgentKind
        /// Nil until the Agent has run a turn.
        public var status: AgentStatus?
        public var unread: Bool
        /// The id that the Agent's CLI gives its conversation. Nil until the Agent reports it.
        public var conversation: String?

        public init(kind: AgentKind, status: AgentStatus?, unread: Bool, conversation: String? = nil) {
            self.kind = kind
            self.status = status
            self.unread = unread
            self.conversation = conversation
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(kind, forKey: .kind)
            try values.encode(status, forKey: .status)
            try values.encode(unread, forKey: .unread)
            try values.encode(conversation, forKey: .conversation)
        }

        private enum CodingKeys: String, CodingKey { case kind, status, unread, conversation }
    }

    public var id: String
    public var windowID: String
    public var index: Int
    public var active: Bool
    public var command: String
    public var path: String
    /// What the Sidebar calls the Pane.
    public var label: String
    /// Nil when no Agent runs in the Pane, including a Pane that an Agent left at a plain shell.
    public var agent: AgentState?

    public init(_ pane: TmuxPane) {
        id = pane.id
        windowID = pane.windowID
        index = pane.index
        active = pane.isActive
        command = pane.command
        path = pane.path
        label = pane.label
        agent = AgentKind(rawValue: pane.agent).flatMap { kind in
            Agent.runs(in: pane) ? AgentState(kind: kind, status: AgentStatus(rawValue: pane.agentStatus), unread: pane.unread,
                                                conversation: pane.agentConversation.isEmpty ? nil : pane.agentConversation) : nil
        }
    }

    // Synthesized encoding leaves out a nil key. A reader gets every key, with null for no Agent or no Status.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(windowID, forKey: .windowID)
        try values.encode(index, forKey: .index)
        try values.encode(active, forKey: .active)
        try values.encode(command, forKey: .command)
        try values.encode(path, forKey: .path)
        try values.encode(label, forKey: .label)
        try values.encode(agent, forKey: .agent)
    }

    private enum CodingKeys: String, CodingKey {
        case id, index, active, command, path, label, agent
        case windowID = "window_id"
    }
}
