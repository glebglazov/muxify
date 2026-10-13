public enum AgentUnread {
    public static func change(for pane: TmuxPane, previousStatus: String?, visited: Bool, manualRead: Bool) -> Bool? {
        let reading = visited && !manualRead
        let isAgent = Agent.runs(in: pane)
        if pane.unread {
            return !isAgent || reading ? false : nil
        }
        if isAgent, !reading, let previousStatus, previousStatus != pane.agentStatus,
           AgentStatus(rawValue: pane.agentStatus)?.needsAttention == true {
            return true
        }
        return nil
    }
}
