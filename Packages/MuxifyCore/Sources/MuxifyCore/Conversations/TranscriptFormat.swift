import Foundation

/// An Entry as a vendor decoder gives it, before the reader numbers it.
struct EntryPart {
    let at: Date?
    let role: Entry.Role
    var tool: String? = nil
    let text: String
}

/// How each Agent CLI writes a conversation. These formats are not a public contract, so a record that a decoder does
/// not know gives no Entries. Thinking is never an Entry, and each part of a vendor message is an Entry of its own.
enum TranscriptFormat {
    /// One JSON record on each line. `toolNames` maps the id of a tool call to its tool, for the result that comes later.
    case jsonLines((_ record: [String: Any], _ toolNames: inout [String: String]) -> [EntryPart])
    /// One JSON document, as `opencode export` prints it.
    case document((_ root: Any) -> [EntryPart])

    static func of(_ kind: AgentKind) -> TranscriptFormat {
        switch kind {
        case .claude: return .jsonLines(claude)
        case .codex: return .jsonLines(codex)
        case .pi: return .jsonLines(pi)
        case .opencode: return .document(opencode)
        }
    }

    private static func claude(_ record: [String: Any], _ toolNames: inout [String: String]) -> [EntryPart] {
        guard let type = record["type"] as? String, type == "user" || type == "assistant", record["isMeta"] as? Bool != true,
              let message = record["message"] as? [String: Any], message["role"] as? String == type else { return [] }
        let at = date(record["timestamp"])
        let role: Entry.Role = type == "user" ? .user : .assistant
        if let text = message["content"] as? String { return [EntryPart(at: at, role: role, text: text)] }
        return (message["content"] as? [[String: Any]] ?? []).compactMap { part in
            switch part["type"] as? String {
            case "text":
                return (part["text"] as? String).map { EntryPart(at: at, role: role, text: $0) }
            case "tool_use":
                let name = part["name"] as? String ?? ""
                if let id = part["id"] as? String { toolNames[id] = name }
                return EntryPart(at: at, role: .toolCall, tool: name, text: compactJSON(part["input"]))
            case "tool_result":
                return EntryPart(at: at, role: .toolResult, tool: (part["tool_use_id"] as? String).flatMap { toolNames[$0] },
                                 text: text(of: part["content"]))
            default:
                return nil
            }
        }
    }

    /// Codex writes each message twice: as an event and as a model response item. Messages come from the events, which
    /// leave out the instructions that Codex adds to the conversation, and tool calls come from the response items.
    private static func codex(_ record: [String: Any], _ toolNames: inout [String: String]) -> [EntryPart] {
        guard let payload = record["payload"] as? [String: Any] else { return [] }
        let at = date(record["timestamp"])
        switch (record["type"] as? String, payload["type"] as? String) {
        case ("event_msg", "user_message"):
            return (payload["message"] as? String).map { [EntryPart(at: at, role: .user, text: $0)] } ?? []
        case ("event_msg", "agent_message"):
            return (payload["message"] as? String).map { [EntryPart(at: at, role: .assistant, text: $0)] } ?? []
        case ("event_msg", "item_completed"):
            guard let item = payload["item"] as? [String: Any] else { return [] }
            let role: Entry.Role
            switch item["type"] as? String {
            case "UserMessage": role = .user
            case "AgentMessage": role = .assistant
            default: return []
            }
            return (item["content"] as? [[String: Any]] ?? []).compactMap { part in
                (part["type"] as? String)?.lowercased() == "text" ? (part["text"] as? String).map { EntryPart(at: at, role: role, text: $0) } : nil
            }
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
            let name = payload["name"] as? String ?? ""
            if let id = payload["call_id"] as? String { toolNames[id] = name }
            let input = payload["arguments"] as? String ?? payload["input"] as? String ?? ""
            let parsed = (try? JSONSerialization.jsonObject(with: Data(input.utf8), options: .fragmentsAllowed))
            return [EntryPart(at: at, role: .toolCall, tool: name, text: parsed.map(compactJSON) ?? input)]
        case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
            return [EntryPart(at: at, role: .toolResult, tool: (payload["call_id"] as? String).flatMap { toolNames[$0] },
                              text: text(of: payload["output"]))]
        default:
            return []
        }
    }

    private static func pi(_ record: [String: Any], _ toolNames: inout [String: String]) -> [EntryPart] {
        guard record["type"] as? String == "message", let message = record["message"] as? [String: Any] else { return [] }
        let at = date(record["timestamp"])
        let role: Entry.Role
        switch message["role"] as? String {
        case "user": role = .user
        case "assistant": role = .assistant
        case "toolResult":
            return [EntryPart(at: at, role: .toolResult, tool: message["toolName"] as? String, text: text(of: message["content"]))]
        default: return []
        }
        if let text = message["content"] as? String { return [EntryPart(at: at, role: role, text: text)] }
        return (message["content"] as? [[String: Any]] ?? []).compactMap { part in
            switch part["type"] as? String {
            case "text": return (part["text"] as? String).map { EntryPart(at: at, role: role, text: $0) }
            case "toolCall": return EntryPart(at: at, role: .toolCall, tool: part["name"] as? String, text: compactJSON(part["arguments"]))
            default: return nil
            }
        }
    }

    /// OpenCode keeps a tool call and its result in one part, so that part gives two Entries.
    private static func opencode(_ root: Any) -> [EntryPart] {
        guard let messages = (root as? [String: Any])?["messages"] as? [[String: Any]] else { return [] }
        return messages.flatMap { message -> [EntryPart] in
            let info = message["info"] as? [String: Any]
            let role: Entry.Role
            switch info?["role"] as? String {
            case "user": role = .user
            case "assistant": role = .assistant
            default: return []
            }
            let at = ((info?["time"] as? [String: Any])?["created"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            return (message["parts"] as? [[String: Any]] ?? []).flatMap { part -> [EntryPart] in
                switch part["type"] as? String {
                case "text":
                    return (part["text"] as? String).map { [EntryPart(at: at, role: role, text: $0)] } ?? []
                case "tool":
                    let name = part["tool"] as? String
                    let state = part["state"] as? [String: Any]
                    let call = EntryPart(at: at, role: .toolCall, tool: name, text: compactJSON(state?["input"]))
                    guard let output = state?["output"] as? String ?? state?["error"] as? String else { return [call] }
                    return [call, EntryPart(at: at, role: .toolResult, tool: name, text: output)]
                default:
                    return []
                }
            }
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    /// A tool result is a string, or a list of parts of which only the text parts count.
    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        return (content as? [[String: Any]] ?? []).compactMap { part in
            ["text", "input_text", "output_text"].contains(part["type"] as? String ?? "") ? part["text"] as? String : nil
        }.joined(separator: "\n")
    }

    private static func compactJSON(_ value: Any?) -> String {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value,
                                                                options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
