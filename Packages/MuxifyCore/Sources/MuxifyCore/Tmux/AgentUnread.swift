public enum AgentReading {
    case away, viewing, visiting
}

public enum ReadChange {
    case read, unread

    public func applies(unread: Bool, status: AgentStatus?) -> Bool {
        switch self {
        case .read: return unread
        case .unread: return !unread && status?.needsAttention == true
        }
    }
}

public enum AgentUnread {
    public static func change(for pane: TmuxPane, previousStatus: String?, reading: AgentReading, manualRead: Bool) -> Bool? {
        let suppressUpdate = reading != .away && !manualRead
        let isAgent = Agent.runs(in: pane)
        if pane.unread {
            return !isAgent || (reading == .visiting && !manualRead) ? false : nil
        }
        if isAgent, !suppressUpdate, let previousStatus, previousStatus != pane.agentStatus,
           AgentStatus(rawValue: pane.agentStatus)?.needsAttention == true {
            return true
        }
        return nil
    }
}
