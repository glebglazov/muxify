import Foundation

/// One message, tool call or tool result in an Agent's conversation.
public struct Entry: Hashable, Sendable {
    public enum Role: String, CaseIterable, Codable, Sendable {
        case user, assistant
        case toolCall = "tool_call"
        case toolResult = "tool_result"

        public var isTool: Bool { self == .toolCall || self == .toolResult }
    }

    /// The position in the whole decoded conversation. It does not change while the vendor only adds to the
    /// Transcript, and no selection changes it.
    public let index: Int
    public let at: Date?
    public let role: Role
    /// The tool's name, for a tool call or a tool result.
    public let tool: String?
    /// For a tool call, the tool input as compact JSON.
    public let text: String

    public init(index: Int, at: Date?, role: Role, tool: String? = nil, text: String) {
        self.index = index
        self.at = at
        self.role = role
        self.tool = tool
        self.text = text
    }
}

/// An Agent's conversation: the kind of its CLI and the id that the CLI gives it.
public struct AgentConversation: Hashable, Sendable {
    public let kind: AgentKind
    public let id: String

    public init(kind: AgentKind, id: String) {
        self.kind = kind
        self.id = id
    }

    /// The id becomes part of a file name or a command line, so it may hold only letters, digits, `_` and `-`.
    public var hasSafeID: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return !id.isEmpty && id.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// The conversation of the Agent that runs in `pane`. Nil when no Agent runs there or it has no id yet.
    public init?(in pane: TmuxPane) {
        guard Agent.runs(in: pane), let kind = AgentKind(rawValue: pane.agent), !pane.agentConversation.isEmpty else { return nil }
        self.init(kind: kind, id: pane.agentConversation)
    }
}

extension TopicRecord {
    /// The conversations of the Agents in the Topic's live Panes, then those that its remembered Sessions keep,
    /// each id once.
    public func agentConversations(in snapshot: TmuxSnapshot) -> [AgentConversation] {
        let windowIDs = Set(snapshot.windows.filter { $0.topicID == id }.map(\.id))
        var conversations = snapshot.panes.filter { windowIDs.contains($0.windowID) }.compactMap(AgentConversation.init(in:))
        func remembered(_ fields: JSONValue) -> AgentConversation? {
            guard let kind = fields["agent"]?.string.flatMap(AgentKind.init(rawValue:)),
                  let id = fields["agent_conversation"]?.string, !id.isEmpty else { return nil }
            return AgentConversation(kind: kind, id: id)
        }
        for window in sessions.flatMap({ $0["windows"]?.array ?? [] }) {
            conversations += [window].compactMap(remembered) + (window["panes"]?.array ?? []).compactMap(remembered)
        }
        var seen: Set<String> = []
        return conversations.filter { seen.insert($0.id).inserted }
    }
}
