import Foundation
import Darwin
import MuxifyCore

struct TopicTitleSuggester {
    enum Source {
        case topic(TopicRecord, TmuxSnapshot, [Project])
        case newTopic(TmuxPane?, Project?)
    }

    struct Conversation: Hashable {
        let kind: AgentKind
        let id: String
    }

    enum CommandOutcome: Equatable {
        case completed(status: Int32, stdout: String, stderr: String)
        case timedOut(stderr: String)
        case launchFailed(String)
    }

    struct CommandFailure: Equatable {
        let command: String
        let detail: String
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        case invalidConversationID(AgentKind, String)
        case noConversationText
        case promptMetadataTooLong
        case commandsFailed([CommandFailure])

        var description: String {
            switch self {
            case .invalidConversationID(let kind, _):
                return "The \(kind.displayName) conversation id is not safe to read."
            case .noConversationText:
                return "No user messages were found in the Topic's Agent conversations."
            case .promptMetadataTooLong:
                return "The Project names and prompt instructions exceed 8,000 characters."
            case .commandsFailed(let failures):
                return failures.map { "\($0.command): \($0.detail)" }.joined(separator: "\n")
            }
        }
    }

    typealias TranscriptLoader = (Conversation) throws -> [String]
    typealias ModelCall = (_ command: String, _ prompt: String, _ timeout: TimeInterval) -> CommandOutcome

    private static let instruction = "Give a short title for this work, at most 5 words. Return plain text on one line."
    private let commands: [String]
    private let commandTimeout: TimeInterval
    private let homeDirectory: URL
    private let transcriptLoader: TranscriptLoader?
    private let modelCall: ModelCall

    init(commands: [String], commandTimeout: TimeInterval = 30,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         transcriptLoader: TranscriptLoader? = nil, modelCall: ModelCall? = nil) {
        self.commands = commands
        self.commandTimeout = commandTimeout
        self.homeDirectory = homeDirectory
        self.transcriptLoader = transcriptLoader
        self.modelCall = modelCall ?? Self.runCommand
    }

    func suggest(for source: Source) throws -> String {
        let request = requestContext(for: source)
        var excerpts: [ConversationExcerpt] = []
        for conversation in request.conversations {
            try validate(conversation)
            let messages = try transcriptLoader?(conversation) ?? loadTranscript(conversation)
            let excerpt = ConversationExcerpt(conversation: conversation, messages: messages)
            if !excerpt.messages.isEmpty { excerpts.append(excerpt) }
        }
        guard !excerpts.isEmpty else { throw Failure.noConversationText }
        let prompt = try makePrompt(projectNames: request.projectNames, excerpts: &excerpts)
        var failures: [CommandFailure] = []
        for command in commands {
            switch modelCall(command, prompt, commandTimeout) {
            case .completed(let status, let stdout, let stderr):
                if status != 0 {
                    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    failures.append(CommandFailure(command: command,
                        detail: "exited with \(status)" + (detail.isEmpty ? "" : ": \(detail)")))
                } else if let title = Self.normalizedTitle(stdout) {
                    return title
                } else {
                    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    failures.append(CommandFailure(command: command,
                        detail: "returned no title" + (detail.isEmpty ? "" : ": \(detail)")))
                }
            case .timedOut(let stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                failures.append(CommandFailure(command: command,
                    detail: "timed out" + (detail.isEmpty ? "" : ": \(detail)")))
            case .launchFailed(let error):
                failures.append(CommandFailure(command: command, detail: "could not start: \(error)"))
            }
        }
        throw Failure.commandsFailed(failures)
    }

    private struct RequestContext {
        let projectNames: [String]
        let conversations: [Conversation]
    }

    private struct ConversationExcerpt {
        let conversation: Conversation
        var messages: [String]

        init(conversation: Conversation, messages: [String]) {
            self.conversation = conversation
            var first: [(Int, String)] = []
            var last: [(Int, String)] = []
            for (index, raw) in messages.enumerated() {
                let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                guard !text.isEmpty else { continue }
                if first.count < 3 { first.append((index, text)) }
                last.append((index, text))
                if last.count > 3 { last.removeFirst() }
            }
            var retained = first
            for item in last where !retained.contains(where: { $0.0 == item.0 }) { retained.append(item) }
            self.messages = retained.sorted { $0.0 < $1.0 }.map(\.1)
        }

        var characterCount: Int { messages.reduce(0) { $0 + $1.count } }
    }

    private func requestContext(for source: Source) -> RequestContext {
        switch source {
        case .newTopic(let pane, let project):
            let conversations = pane.flatMap(Self.conversation(in:)).map { [$0] } ?? []
            return RequestContext(projectNames: project.map { [$0.name] } ?? [], conversations: conversations)
        case .topic(let topic, let snapshot, let projects):
            let windows = snapshot.windows.filter { $0.topicID == topic.id }
            let windowIDs = Set(windows.map(\.id))
            var conversations = snapshot.panes.filter { windowIDs.contains($0.windowID) }
                .compactMap(Self.conversation(in:))
            for session in topic.sessions {
                guard case .array(let rememberedWindows)? = session["windows"] else { continue }
                for window in rememberedWindows {
                    guard let agent = window["agent"]?.string.flatMap(AgentKind.init(rawValue:)),
                          let id = window["agent_conversation"]?.string, !id.isEmpty else { continue }
                    conversations.append(Conversation(kind: agent, id: id))
                }
            }
            var seen: Set<String> = []
            conversations = conversations.filter { seen.insert($0.id).inserted }

            var names: [String] = []
            func project(at path: String) -> Project {
                let folder = Folder.local(path)
                return projects.first { $0.folder == folder } ?? Project(folder: folder, name: URL(fileURLWithPath: path).lastPathComponent)
            }
            func append(_ project: Project?) {
                guard let project, !names.contains(project.displayName) else { return }
                names.append(project.displayName)
            }
            append(topic.homeProject.map(project(at:)))
            for window in windows { append(TopicLocation(of: window, record: topic, projects: projects).project) }
            for session in topic.sessions {
                append(session["project_path"]?.string.map(project(at:)))
            }
            return RequestContext(projectNames: names, conversations: conversations)
        }
    }

    private static func conversation(in pane: TmuxPane) -> Conversation? {
        guard Agent.runs(in: pane), let kind = AgentKind(rawValue: pane.agent), !pane.agentConversation.isEmpty else { return nil }
        return Conversation(kind: kind, id: pane.agentConversation)
    }

    private func validate(_ conversation: Conversation) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !conversation.id.isEmpty,
              conversation.id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw Failure.invalidConversationID(conversation.kind, conversation.id)
        }
    }

    private func makePrompt(projectNames: [String], excerpts: inout [ConversationExcerpt]) throws -> String {
        func render() -> String {
            var lines = [Self.instruction, "", "Projects:"]
            lines += projectNames.isEmpty ? ["- (none)"] : projectNames.map { "- \($0)" }
            lines += ["", "Conversation excerpts:"]
            for (index, excerpt) in excerpts.enumerated() {
                lines.append("[\(excerpt.conversation.kind.displayName) \(index + 1)]")
                lines += excerpt.messages.map { "- \($0)" }
            }
            return lines.joined(separator: "\n")
        }

        let metadata = render()
        if excerpts.allSatisfy({ $0.messages.isEmpty }), metadata.count > 8_000 {
            throw Failure.promptMetadataTooLong
        }
        var prompt = metadata
        while prompt.count > 8_000 {
            guard let index = excerpts.indices.filter({ !excerpts[$0].messages.isEmpty }).max(by: {
                if excerpts[$0].characterCount == excerpts[$1].characterCount { return $0 > $1 }
                return excerpts[$0].characterCount < excerpts[$1].characterCount
            }) else { throw Failure.promptMetadataTooLong }
            excerpts[index].messages.removeLast()
            prompt = render()
        }
        return prompt
    }

    static func normalizedTitle(_ output: String) -> String? {
        guard var title = output.split(whereSeparator: \Character.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) else { return nil }
        if title.count >= 2, let first = title.first, let last = title.last,
           first == last, first == "\"" || first == "'" {
            title.removeFirst()
            title.removeLast()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !title.isEmpty else { return nil }
        return String(title.prefix(60))
    }

    private func loadTranscript(_ conversation: Conversation) throws -> [String] {
        switch conversation.kind {
        case .claude:
            return firstTranscript(in: homeDirectory.appendingPathComponent(".claude/projects"), matches: { url in
                url.lastPathComponent == conversation.id + ".jsonl"
            }).map { readJSONLines($0, kind: .claude) } ?? []
        case .codex:
            return firstTranscript(in: homeDirectory.appendingPathComponent(".codex/sessions"), matches: { url in
                url.lastPathComponent.hasSuffix("-\(conversation.id).jsonl")
            }).map { readJSONLines($0, kind: .codex) } ?? []
        case .pi:
            return firstTranscript(in: homeDirectory.appendingPathComponent(".pi/agent/sessions"), matches: { url in
                url.lastPathComponent.hasSuffix("_\(conversation.id).jsonl")
            }).map { readJSONLines($0, kind: .pi) } ?? []
        case .opencode:
            let command = "opencode export " + Tmux.shellQuote(conversation.id)
            guard case .completed(0, let output, _) = Self.runCommand(command, "", 30),
                  let data = output.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = root["messages"] as? [[String: Any]] else { return [] }
            return messages.compactMap { message in
                guard (message["info"] as? [String: Any])?["role"] as? String == "user",
                      let parts = message["parts"] as? [[String: Any]] else { return nil }
                let text = parts.compactMap { part in
                    part["type"] as? String == "text" ? part["text"] as? String : nil
                }.joined(separator: "\n")
                return text.isEmpty ? nil : text
            }
        }
    }

    private func firstTranscript(in root: URL, matches: (URL) -> Bool) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                               options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator where matches(url) { return url }
        return nil
    }

    private func readJSONLines(_ url: URL, kind: AgentKind) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var pending = Data()
        var messages = BoundedMessages()
        while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                if let message = Self.userMessage(in: Data(line), kind: kind) { messages.append(message) }
            }
        }
        if !pending.isEmpty, let message = Self.userMessage(in: pending, kind: kind) { messages.append(message) }
        return messages.values
    }

    private struct BoundedMessages {
        private var first: [(Int, String)] = []
        private var last: [(Int, String)] = []
        private var index = 0

        mutating func append(_ raw: String) {
            let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            defer { index += 1 }
            guard !text.isEmpty else { return }
            let item = (index, text)
            if first.count < 3 { first.append(item) }
            last.append(item)
            if last.count > 3 { last.removeFirst() }
        }

        var values: [String] {
            var retained = first
            for item in last where !retained.contains(where: { $0.0 == item.0 }) { retained.append(item) }
            return retained.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func userMessage(in data: Data, kind: AgentKind) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch kind {
        case .claude:
            guard object["isMeta"] as? Bool != true,
                  object["type"] as? String == "user", let message = object["message"] as? [String: Any],
                  message["role"] as? String == "user" else { return nil }
            if let text = message["content"] as? String { return text }
            return (message["content"] as? [[String: Any]])?.compactMap {
                $0["type"] as? String == "text" ? $0["text"] as? String : nil
            }.joined(separator: "\n")
        case .codex:
            guard object["type"] as? String == "event_msg", let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message" else { return nil }
            return payload["message"] as? String
        case .pi:
            guard object["type"] as? String == "message", let message = object["message"] as? [String: Any],
                  message["role"] as? String == "user", let content = message["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        case .opencode:
            return nil
        }
    }

    private static func runCommand(_ command: String, _ input: String, _ timeout: TimeInterval) -> CommandOutcome {
        func failed(_ operation: String, _ code: Int32 = errno) -> CommandOutcome {
            .launchFailed("\(operation): \(String(cString: strerror(code)))")
        }
        func closeAll(_ descriptors: [Int32]) {
            for descriptor in descriptors where descriptor >= 0 { Darwin.close(descriptor) }
        }

        var inputPipe = [Int32](repeating: -1, count: 2)
        var outputPipe = [Int32](repeating: -1, count: 2)
        var errorPipe = [Int32](repeating: -1, count: 2)
        guard pipe(&inputPipe) == 0 else { return failed("stdin pipe") }
        guard pipe(&outputPipe) == 0 else {
            closeAll(inputPipe)
            return failed("stdout pipe")
        }
        guard pipe(&errorPipe) == 0 else {
            closeAll(inputPipe + outputPipe)
            return failed("stderr pipe")
        }
        let descriptors = inputPipe + outputPipe + errorPipe

        var actions: posix_spawn_file_actions_t? = nil
        let actionsResult = posix_spawn_file_actions_init(&actions)
        guard actionsResult == 0 else {
            closeAll(descriptors)
            return failed("spawn file actions", actionsResult)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        let actionResults = [
            posix_spawn_file_actions_adddup2(&actions, inputPipe[0], STDIN_FILENO),
            posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&actions, errorPipe[1], STDERR_FILENO),
        ] + descriptors.map { posix_spawn_file_actions_addclose(&actions, $0) }
        if let result = actionResults.first(where: { $0 != 0 }) {
            closeAll(descriptors)
            return failed("spawn file action", result)
        }

        var attributes: posix_spawnattr_t? = nil
        let attributesResult = posix_spawnattr_init(&attributes)
        guard attributesResult == 0 else {
            closeAll(descriptors)
            return failed("spawn attributes", attributesResult)
        }
        defer { posix_spawnattr_destroy(&attributes) }
        let groupResults = [
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)),
            posix_spawnattr_setpgroup(&attributes, 0),
        ]
        if let result = groupResults.first(where: { $0 != 0 }) {
            closeAll(descriptors)
            return failed("spawn process group", result)
        }

        let arguments = ["zsh", "-l", "-c", command]
        var argumentPointers = arguments.map { strdup($0) } + [nil]
        defer { for case let pointer? in argumentPointers { free(pointer) } }
        var pid: pid_t = 0
        let spawnResult = argumentPointers.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(&pid, "/bin/zsh", &actions, &attributes, buffer.baseAddress!, environ)
        }
        guard spawnResult == 0 else {
            closeAll(descriptors)
            return failed("could not start", spawnResult)
        }

        closeAll([inputPipe[0], outputPipe[1], errorPipe[1]])
        let inputHandle = FileHandle(fileDescriptor: inputPipe[1], closeOnDealloc: true)
        let outputHandle = FileHandle(fileDescriptor: outputPipe[0], closeOnDealloc: true)
        let errorHandle = FileHandle(fileDescriptor: errorPipe[0], closeOnDealloc: true)
        let readGroup = DispatchGroup()
        var outputData = Data(), errorData = Data()
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputData = outputHandle.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorData = errorHandle.readDataToEndOfFile()
            readGroup.leave()
        }
        do {
            try inputHandle.write(contentsOf: Data(input.utf8))
            try inputHandle.close()
        } catch {
            kill(-pid, SIGKILL)
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            readGroup.wait()
            return .launchFailed(String(describing: error))
        }

        var status: Int32 = 0
        func wait(noHang: Bool) -> pid_t {
            var result: pid_t
            repeat { result = waitpid(pid, &status, noHang ? WNOHANG : 0) } while result == -1 && errno == EINTR
            return result
        }
        let timeoutNanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var waited = wait(noHang: true)
        while waited == 0, DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(10_000)
            waited = wait(noHang: true)
        }
        var timedOut = waited == 0
        if waited > 0, readGroup.wait(timeout: DispatchTime(uptimeNanoseconds: deadline)) == .timedOut {
            timedOut = true
        }
        if timedOut {
            kill(-pid, SIGTERM)
            let grace = DispatchTime.now() + .seconds(1)
            while waited == 0, DispatchTime.now().uptimeNanoseconds < grace.uptimeNanoseconds {
                usleep(10_000)
                waited = wait(noHang: true)
            }
            if readGroup.wait(timeout: grace) == .timedOut { kill(-pid, SIGKILL) }
            if waited == 0 {
                kill(-pid, SIGKILL)
                waited = wait(noHang: false)
            }
        } else if waited == -1 {
            kill(-pid, SIGKILL)
            _ = wait(noHang: false)
        }
        readGroup.wait()
        let stderr = String(decoding: errorData, as: UTF8.self)
        if timedOut { return .timedOut(stderr: stderr) }
        if waited == -1 { return failed("wait for command") }
        let signal = status & 0x7f
        let exitStatus = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        return .completed(status: exitStatus, stdout: String(decoding: outputData, as: UTF8.self), stderr: stderr)
    }
}
