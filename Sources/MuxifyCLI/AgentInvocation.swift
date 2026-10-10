import Foundation
import MuxifyCore

/// One `muxify agent` command line. `agent list` prints every Agent on the tmux server with its Status, Unread and
/// Topic. It reads the Topic records and one tmux snapshot, and changes nothing.
struct AgentInvocation: Equatable {
    /// An open Topic's id or label, as `--topic` takes it elsewhere.
    var topic: String?
    var status: AgentStatus?
    var unreadOnly: Bool
    var output: TopicInvocation.Output
    var paths: MuxifyPaths
}

extension AgentInvocation {
    /// Parses the words after `agent`. A command line that the command cannot run is a usage error, status 2.
    init(arguments: ArraySlice<String>, environment: [String: String]) throws {
        let usageError = CLIError(CLICommand.usage, exitCode: 2)
        var args = arguments
        guard args.popFirst() == "list" else { throw usageError }
        var topic: String?
        var status: AgentStatus?
        var unreadOnly = false
        var output = TopicInvocation.Output.text
        while let argument = args.popFirst() {
            switch argument {
            case "--topic":
                guard topic == nil, let value = args.popFirst() else { throw usageError }
                topic = try TopicInvocation.TargetOption.topicName(value)
            case "--status":
                guard status == nil, let value = args.popFirst() else { throw usageError }
                guard let parsed = AgentStatus(rawValue: value) else {
                    throw CLIError("--status takes working, blocked, done or failed", exitCode: 2)
                }
                status = parsed
            case "--unread": unreadOnly = true
            case "--json": output = .json
            default: throw usageError
            }
        }
        self.init(topic: topic, status: status, unreadOnly: unreadOnly, output: output,
                  paths: MuxifyPaths(environment: environment, home: environment["HOME"] ?? NSHomeDirectory()))
    }

    func run() async throws {
        let records: [TopicRecord]
        do {
            records = try TopicStore(paths: paths).read().records
        } catch {
            throw CLIError("Muxify could not read the Topic records in \(paths.state.path). \(error.localizedDescription)")
        }
        let topicID: String?
        do {
            topicID = try topic.map { try TopicRef.named($0).resolve(in: records).id }
        } catch let error as TopicRequestError {
            throw CLIError(error.description)
        }
        // No tmux server gives no Panes, so no Agents.
        let rows = AgentRow.list(snapshot: TmuxServer.local.snapshot(), records: records).filter { row in
            (topicID == nil || row.topic?.id == topicID)
                && (status == nil || row.agent.status == status)
                && (!unreadOnly || row.agent.unread)
        }
        switch output {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(AgentList(agents: rows)), as: UTF8.self))
        case .text:
            for row in rows {
                print([row.paneID, row.agent.kind.rawValue, row.agent.status?.rawValue ?? "", row.agent.unread ? "unread" : "",
                       row.topic?.label ?? "", row.sessionName].map(\.oneLineField).joined(separator: "\t"))
            }
        }
    }
}

/// One Agent as `agent list` prints it: its Pane, where the Pane is, and the open Topic of its Session.
struct AgentRow: Encodable, Equatable {
    let paneID: String
    let windowID: String
    let sessionID: String
    let sessionName: String
    let agent: PaneSummary.AgentState
    /// Nil when the Session is in no open Topic.
    let topic: TopicSummary?

    /// The Agents in tmux order.
    static func list(snapshot: TmuxSnapshot, records: [TopicRecord]) -> [AgentRow] {
        let windows = Dictionary(snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let open = Dictionary(records.filter { $0.settledAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return snapshot.panes.compactMap { pane in
            guard let agent = PaneSummary(pane).agent, let window = windows[pane.windowID] else { return nil }
            return AgentRow(paneID: pane.id, windowID: window.id, sessionID: window.sessionID, sessionName: window.sessionName,
                            agent: agent, topic: window.topicID.flatMap { open[$0] }.map(TopicSummary.init(record:)))
        }
    }

    // Synthesized encoding leaves out a nil key. A reader gets every key, with null for No Topic.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(paneID, forKey: .paneID)
        try values.encode(windowID, forKey: .windowID)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(sessionName, forKey: .sessionName)
        try values.encode(agent, forKey: .agent)
        try values.encode(topic, forKey: .topic)
    }

    private enum CodingKeys: String, CodingKey {
        case agent, topic
        case paneID = "pane_id", windowID = "window_id", sessionID = "session_id", sessionName = "session_name"
    }
}

/// The `--json` form of `agent list`.
private struct AgentList: Encodable {
    let agents: [AgentRow]
}
