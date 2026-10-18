import Foundation

/// The folders in which the Agent CLIs keep their Transcripts. OpenCode keeps none: `opencode export` prints a
/// conversation.
public struct TranscriptRoots: Equatable, Sendable {
    public let claude: URL
    public let codex: URL
    public let pi: URL

    /// Honors CLAUDE_CONFIG_DIR and CODEX_HOME, as the CLIs do.
    public init(environment: [String: String], home: URL) {
        func folder(_ name: String) -> URL? { environment[name].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } }
        claude = (folder("CLAUDE_CONFIG_DIR") ?? home.appendingPathComponent(".claude")).appendingPathComponent("projects")
        codex = (folder("CODEX_HOME") ?? home.appendingPathComponent(".codex")).appendingPathComponent("sessions")
        pi = home.appendingPathComponent(".pi/agent/sessions")
    }

    /// The folder that holds every Transcript of `kind`, at any depth.
    public func folder(for kind: AgentKind) -> URL? {
        switch kind {
        case .claude: return claude
        case .codex: return codex
        case .pi: return pi
        case .opencode: return nil
        }
    }

    /// The Transcript file of `conversation`. Nil when its folder has none, or when the id is not safe to read.
    public func transcript(of conversation: AgentConversation) -> URL? {
        guard conversation.hasSafeID, let root = folder(for: conversation.kind) else { return nil }
        let id = conversation.id
        let matches: (String) -> Bool
        switch conversation.kind {
        case .claude: matches = { $0 == id + ".jsonl" }
        case .codex: matches = { $0.hasSuffix("-\(id).jsonl") }
        case .pi: matches = { $0.hasSuffix("_\(id).jsonl") }
        case .opencode: return nil
        }
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles]) else { return nil }
        for case let file as URL in files where matches(file.lastPathComponent) { return file }
        return nil
    }

    /// The kind whose folder holds `file`, through symlinks too.
    public func kind(ofTranscriptAt file: URL) -> AgentKind? {
        let path = file.resolvingSymlinksInPath().path
        return AgentKind.allCases.first { kind in
            folder(for: kind).map { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") } ?? false
        }
    }
}

/// Reads a Transcript into Entries, numbered in the order of the conversation.
public enum TranscriptReader {
    /// Reads the file line by line. The Agent can be writing its last line, so a last line without a newline counts
    /// only when it is complete JSON.
    public static func entries(inFile file: URL, kind: AgentKind) throws -> [Entry] {
        guard case .jsonLines(let decode) = TranscriptFormat.of(kind) else {
            return entries(in: try Data(contentsOf: file), kind: kind)
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var lines = LineDecoder(decode: decode)
        var pending = Data()
        while let chunk = try handle.read(upToCount: 1 << 16), !chunk.isEmpty {
            pending.append(chunk)
            var start = pending.startIndex
            while let newline = pending[start...].firstIndex(of: 0x0A) {
                lines.append(pending[start..<newline])
                start = newline + 1
            }
            pending.removeSubrange(..<start)
        }
        lines.append(pending)
        return lines.entries
    }

    /// Reads a whole Transcript, or the output of `opencode export`.
    public static func entries(in data: Data, kind: AgentKind) -> [Entry] {
        switch TranscriptFormat.of(kind) {
        case .jsonLines(let decode):
            var lines = LineDecoder(decode: decode)
            for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) { lines.append(line) }
            return lines.entries
        case .document(let decode):
            guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
            return number(decode(root))
        }
    }

    private struct LineDecoder {
        let decode: ([String: Any], inout [String: String]) -> [EntryPart]
        var toolNames: [String: String] = [:]
        var parts: [EntryPart] = []

        mutating func append(_ line: Data) {
            guard !line.isEmpty, let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            parts += decode(record, &toolNames)
        }

        var entries: [Entry] { number(parts) }
    }

    private static func number(_ parts: [EntryPart]) -> [Entry] {
        parts.enumerated().map { index, part in Entry(index: index, at: part.at, role: part.role, tool: part.tool, text: part.text) }
    }
}
