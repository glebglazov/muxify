import Foundation
import MuxifyCore

/// One `muxify topic` command line. It runs the Topic service in this process, on the records under `paths`,
/// so it works without Muxify running. The service chooses what the request acts on: `target`, else `caller`.
struct TopicInvocation: Equatable {
    enum Command: Equatable {
        /// A `project` is as typed; it resolves to a real directory when the command runs.
        case new(title: String?, project: String?)
        /// `directory` resolves to its row of the New Topic list. `newWorktree` asks for a new Worktree from that
        /// row's Worktree, at its HEAD or at the ref `base`.
        case addProject(directory: String, newWorktree: Bool, base: String?)
        /// `removeWorktrees` removes each Worktree that the Settle sheet offers to remove, as if each box were selected.
        case settle(removeWorktrees: Bool)
        case forget(removeWorktrees: Bool)
        case list
        case show
        /// `project` is as typed and limits the run to the Session that uses it. `command` is the argument vector
        /// after `--`; it runs once per live Session, never in a Pane.
        case exec(project: String?, timeout: TimeInterval, command: [String])
        /// The git status of each live Session, or of the one that uses `project`.
        case status(project: String?)
        /// One changeset across the live Sessions since each one's base. `stat` prints a summary, not the patch.
        case diff(project: String?, stat: Bool)

        /// The target options this command takes. A titled Topic in a Project starts its own Session, so it takes none.
        var targets: [TargetOption] {
            switch self {
            case .new(_?, _?): return []
            case .new: return [.window, .pane]
            case .addProject, .settle, .forget, .show, .exec, .status, .diff: return [.topic, .window, .pane]
            case .list: return []
            }
        }

        var needsTarget: Bool { !targets.isEmpty }

        /// The command as the user typed it, for an error message.
        var phrase: String {
            switch self {
            case .new(_?, _?): return "topic new with a title and --project"
            case .new: return "topic new"
            case .addProject: return "topic add-project"
            case .settle: return "topic settle"
            case .forget: return "topic forget"
            case .list: return "topic list"
            case .show: return "topic show"
            case .exec: return "topic exec"
            case .status: return "topic status"
            case .diff: return "topic diff"
            }
        }
    }

    enum TargetOption: String, CaseIterable {
        case topic = "--topic"
        case window = "--window"
        case pane = "--pane"

        var usage: String {
            switch self {
            case .topic: return "--topic <id|label>"
            case .window: return "--window <id>"
            case .pane: return "--pane <id>"
            }
        }

        func target(_ value: String) throws -> TopicTarget {
            switch self {
            case .topic:
                return .topic(.named(try Self.topicName(value)))
            case .window:
                guard let id = WindowID(rawValue: value) else { throw CLIError("--window takes a tmux Window id, e.g. @12", exitCode: 2) }
                return .window(id)
            case .pane:
                guard let id = PaneID(rawValue: value) else { throw CLIError("--pane takes a tmux Pane id, e.g. %3", exitCode: 2) }
                return .pane(id)
            }
        }

        /// The id or label of an open Topic, as every `--topic` takes it.
        static func topicName(_ value: String) throws -> String {
            guard !value.isEmpty else { throw CLIError("--topic takes the id or label of an open Topic", exitCode: 2) }
            return value
        }
    }

    /// The target options of one command line, and the caller Pane that `TMUX_PANE` names. A command acts on its
    /// target, else on the caller Pane's Window or Topic.
    struct TargetOptions {
        let accepted: [TargetOption]
        private(set) var chosen: (option: TargetOption, target: TopicTarget)?

        init(accepting accepted: [TargetOption]) {
            self.accepted = accepted
        }

        /// Takes `argument` and its value from `args` when it is an accepted target option. False for any other word.
        mutating func take(_ argument: String, from args: inout ArraySlice<String>) throws -> Bool {
            guard let option = TargetOption(rawValue: argument), accepted.contains(option) else { return false }
            guard chosen == nil else {
                let names = accepted.map(\.rawValue)
                throw CLIError("give only one of " + names.dropLast().joined(separator: ", ") + " and " + names.last!, exitCode: 2)
            }
            guard let value = args.popFirst() else { throw CLIError(CLICommand.usage, exitCode: 2) }
            chosen = (option, try option.target(value))
            return true
        }

        /// The caller Pane, or nil outside tmux. When `needed` and no option chose a target, a missing caller Pane is
        /// a usage error that names the `offered` options.
        func caller(environment: [String: String], needed: Bool, offered: [TargetOption]) throws -> PaneID? {
            let pane = environment["TMUX_PANE"].flatMap { $0.isEmpty ? nil : $0 }
            let caller = pane.flatMap(PaneID.init(rawValue:))
            if needed, chosen == nil, caller == nil {
                let problem = pane.map { "TMUX_PANE \($0) is not a tmux Pane id" } ?? "not inside tmux"
                throw CLIError(problem + TopicInvocation.choice(of: offered), exitCode: 2)
            }
            return caller
        }
    }

    enum Output: Equatable {
        /// Each changed Topic's id, the list as `topic list` has always printed it, or a short `topic show`.
        case text
        /// The whole `TopicResponse` as one JSON line.
        case json
    }

    var command: Command
    var target: TopicTarget?
    var caller: PaneID?
    var output: Output
    var paths: MuxifyPaths
}

extension TopicInvocation {
    /// Parses the words after `topic`. A command line that the commands cannot run is a usage error, status 2.
    init(arguments: ArraySlice<String>, environment: [String: String]) throws {
        let usageError = CLIError(CLICommand.usage, exitCode: 2)
        var args = arguments
        guard let name = args.popFirst() else { throw usageError }
        var words: [String] = []
        var project: String?
        var newWorktree = false
        var base: String?
        var removeWorktrees = false
        var timeout: TimeInterval?
        var execArguments: [String]?
        var stat = false
        var targets = TargetOptions(accepting: TargetOption.allCases)
        var output = Output.text
        while let argument = args.popFirst() {
            if try targets.take(argument, from: &args) {
                continue
            } else if argument == "--project" {
                guard project == nil, let value = args.popFirst(), !value.isEmpty, !value.hasPrefix("-") else { throw usageError }
                project = value
            } else if argument == "--worktree" {
                newWorktree = true
            } else if argument == "--base" {
                guard base == nil, let value = args.popFirst(), !value.isEmpty, !value.hasPrefix("-") else { throw usageError }
                base = value
            } else if argument == "--remove-worktrees" {
                removeWorktrees = true
            } else if argument == "--json" {
                output = .json
            } else if argument == "--timeout" {
                guard timeout == nil, let value = args.popFirst(), let seconds = TimeInterval(value), seconds > 0, seconds.isFinite else {
                    throw usageError
                }
                timeout = seconds
            } else if argument == "--stat" {
                stat = true
            } else if argument == "--" {
                execArguments = Array(args)
                args = []
            } else if argument.hasPrefix("-") {
                throw usageError
            } else {
                words.append(argument)
            }
        }
        if name != "add-project", newWorktree || base != nil { throw usageError }
        if name != "settle", name != "forget", removeWorktrees { throw usageError }
        if name != "exec", timeout != nil || execArguments != nil { throw usageError }
        if name != "diff", stat { throw usageError }
        switch (name, words.count, project) {
        case ("new", 0...1, _):
            if let title = words.first, title.allSatisfy(\.isWhitespace) { throw usageError }
            command = .new(title: words.first, project: project)
        case ("add-project", 1, nil) where newWorktree || base == nil:
            command = .addProject(directory: words[0], newWorktree: newWorktree, base: base)
        case ("settle", 0, nil): command = .settle(removeWorktrees: removeWorktrees)
        case ("forget", 0, nil): command = .forget(removeWorktrees: removeWorktrees)
        case ("list", 0, nil): command = .list
        case ("show", 0, nil): command = .show
        case ("exec", 0, _):
            guard let execArguments, !execArguments.isEmpty else { throw usageError }
            command = .exec(project: project, timeout: timeout ?? 60, command: execArguments)
        case ("status", 0, _): command = .status(project: project)
        case ("diff", 0, _): command = .diff(project: project, stat: stat)
        default: throw usageError
        }
        let takes = command.targets
        if let chosen = targets.chosen, !takes.contains(chosen.option) {
            throw CLIError("\(command.phrase) does not take \(chosen.option.rawValue)" + Self.choice(of: takes), exitCode: 2)
        }
        caller = try targets.caller(environment: environment, needed: command.needsTarget, offered: takes)
        target = targets.chosen?.target
        self.output = output
        paths = MuxifyPaths(environment: environment, home: environment["HOME"] ?? NSHomeDirectory())
    }

    static func choice(of options: [TargetOption]) -> String {
        let names = options.map(\.usage)
        guard let last = names.last else { return "" }
        let list = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " or " + last
        return "; name the target with " + list
    }

    func run() async throws {
        let response: TopicResponse
        if command == .list {
            response = TopicService(paths: paths).handle(TopicRequest(.list))
        } else {
            let config = try await ConfigProjects.load(paths.configFile)
            let projects = config.projects
            let service = TopicService(paths: paths, server: .local, projects: projects, sessionOrder: config.topics.sessionOrder)
            // No client: no terminal switches to the result, because a command changes what the user sees only
            // when they ask for it.
            response = service.handle(TopicRequest(try request(projects: projects, service: service), target: target,
                                                   caller: caller.map(TopicCaller.pane)))
        }
        if case .topic(let topic) = response {
            switch command {
            case .exec(let project, let timeout, let arguments):
                let sessions = try TopicExec.sessions(of: topic, project: project.map(Self.directory))
                return try TopicExec(arguments: arguments, timeout: timeout).run(sessions, topic: topic, output: output)
            case .status(let project):
                return try TopicGit(report: .status).run(try TopicExec.sessions(of: topic, project: project.map(Self.directory)),
                                                         topic: topic, output: output)
            case .diff(let project, let stat):
                return try TopicGit(report: .diff(stat: stat)).run(try TopicExec.sessions(of: topic, project: project.map(Self.directory)),
                                                                   topic: topic, output: output)
            default: break
            }
        }
        try Self.report(response, output: output)
    }

    /// Prints a response of the Topic service, and throws its failure so that the command exits with an error.
    static func report(_ response: TopicResponse, output: Output) throws {
        switch output {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(response), as: UTF8.self))
        case .text:
            switch response {
            case .topics(let topics):
                // One line per Topic, so a label keeps no tab or line break.
                for topic in topics {
                    print("\(topic.id)\t\(topic.label.oneLineField)")
                }
            case .topic(let topic):
                // One line for the Topic, then one for each live Session, with tab-separated fields as in topic list.
                print("\(topic.id)\t\(topic.label.oneLineField)")
                for session in topic.sessions {
                    print([session.name, session.project.label, session.worktree?.path ?? session.project.path,
                           session.worktree?.branch ?? ""].map(\.oneLineField).joined(separator: "\t"))
                }
            case .changed(let change): if let id = change.topicID { print(id) }
            case .failed: break
            }
        }
        if case .failed(let failure) = response { throw CLIError(failure) }
    }

    private func request(projects: [Project], service: TopicService) throws -> TopicCommand {
        switch command {
        case .new(nil, let project): return .extract(project: try project.map(Self.directory))
        case .new(let title?, let project): return .create(title: title, project: try project.map(Self.directory))
        case .addProject(let path, let newWorktree, let base):
            let directory = try Self.directory(path)
            // A folder in no Project goes to the service as typed, which fails with the Config's own words.
            guard let choice = ProjectChoice.containing(directory, in: projects) else {
                return .addProject(project: directory, workingCopy: .project)
            }
            if newWorktree, choice.worktree == nil {
                throw CLIError("--worktree needs a git repository, and \(choice.directory) is not one", exitCode: 2)
            }
            // The same choice as the Add Project sheet makes for this row.
            return .addProject(project: choice.project.path, workingCopy: choice.workingCopy(newWorktree: newWorktree, base: base))
        case .forget(let remove):
            guard remove, let target = target ?? caller.map(TopicTarget.pane),
                  let choices = try? service.forgetChoices(for: target).get() else { return .forget(choices: [], worktrees: []) }
            return .forget(choices: choices.sessions, worktrees: choices.worktrees.filter(\.isClean).map(\.id))
        case .settle(false): return .settle(choices: [], outcome: "")
        case .settle(true):
            // Choices that fail to load leave the defaults, so the request itself reports why the Topic cannot settle.
            guard let settled = target ?? caller.map(TopicTarget.pane),
                  var choices = try? service.settleChoices(for: settled).get() else { return .settle(choices: [], outcome: "") }
            for index in choices.indices where choices[index].worktree != nil { choices[index].removeWorktree = true }
            return .settle(choices: choices, outcome: "")
        case .list: return .list
        // exec, status and diff work in the Sessions that `topic show` gives.
        case .show, .exec, .status, .diff: return .show
        }
    }

    /// The directory `path` names, with symlinks resolved, as `cd -P` would reach it.
    static func directory(_ path: String) throws -> String {
        var isDirectory: ObjCBool = false
        guard let resolved = realpath(path, nil) else { throw CLIError(CLICommand.usage, exitCode: 2) }
        defer { free(resolved) }
        let result = String(cString: resolved)
        guard FileManager.default.fileExists(atPath: result, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError(CLICommand.usage, exitCode: 2)
        }
        return result
    }
}
