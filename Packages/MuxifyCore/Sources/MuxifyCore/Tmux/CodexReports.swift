import Foundation

/// Codex's daemon reports by conversation. Its TUI puts that conversation in
/// the Pane title, so the snapshot can join them without the daemon's TMUX.
enum CodexReports {
    private struct Report: Decodable {
        let version: Int
        let conversation: String
        let status: String?
    }

    private static let identifier = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9-])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-(?:[0-9a-f]{12}|[0-9a-f]{5}\.\.\.)(?![A-Za-z0-9.-])"#
    )

    static func prefix(in title: String) -> String? {
        let matches = identifier.matches(in: title, range: NSRange(title.startIndex..., in: title))
        guard matches.count == 1, let range = Range(matches[0].range, in: title) else { return nil }
        let value = String(title[range])
        return value.hasSuffix("...") ? String(value.dropLast(3)) : value
    }

    static func titleForDisplay(_ title: String) -> String {
        guard prefix(in: title) != nil else { return title }
        let text = identifier.stringByReplacingMatches(in: title, range: NSRange(title.startIndex..., in: title), withTemplate: "")
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }

    static func prefixes(in snapshot: TmuxSnapshot) -> [String] {
        Array(Set(snapshot.panes.filter { $0.command == "codex" }.compactMap { prefix(in: $0.title) })).sorted()
    }

    static func readScript(prefixes: [String]) -> String {
        let patterns = prefixes.map { "\"$directory/\($0)\"*.json" }.joined(separator: " ")
        return """
        directory="$HOME/.local/state/muxify/codex"
        for file in \(patterns); do
            [ -f "$file" ] || continue
            printf 'D\(Tmux.separator)'
            head -c 512 "$file" 2>/dev/null | tr -d '\\n\\r'
            printf '\\n'
        done
        """
    }

    static func apply(_ lines: [String], to snapshot: inout TmuxSnapshot) {
        var reports: [String: Report] = [:]
        for line in lines {
            guard let report = try? JSONDecoder().decode(Report.self, from: Data(line.utf8)),
                  report.version == 1, UUID(uuidString: report.conversation) != nil,
                  report.conversation == report.conversation.lowercased(),
                  prefix(in: report.conversation) == report.conversation else { continue }
            reports[report.conversation] = report
        }
        for index in snapshot.panes.indices {
            let pane = snapshot.panes[index]
            guard pane.command == "codex" else {
                if pane.agent == AgentKind.codex.rawValue {
                    snapshot.panes[index].agent = ""
                    snapshot.panes[index].agentStatus = ""
                    snapshot.panes[index].agentConversation = ""
                }
                continue
            }
            let matching = prefix(in: pane.title).map { prefix in
                reports.values.filter { $0.conversation.hasPrefix(prefix) }
            } ?? []
            let report = matching.count == 1 ? matching[0] : nil
            snapshot.panes[index].agent = AgentKind.codex.rawValue
            snapshot.panes[index].agentStatus = report?.status.flatMap(AgentStatus.init(rawValue:))?.rawValue ?? ""
            snapshot.panes[index].agentConversation = report?.conversation ?? ""
        }
        let panes = Dictionary(snapshot.panes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in snapshot.windows.indices {
            if snapshot.windows[index].command == "codex" {
                snapshot.windows[index].agent = AgentKind.codex.rawValue
            } else if snapshot.windows[index].agent == AgentKind.codex.rawValue {
                snapshot.windows[index].agent = panes[snapshot.windows[index].activePaneID]?.agent ?? ""
            }
        }
    }
}
