import Foundation
import MuxifyCore

enum CLICommand: Equatable {
    case help
    case browserOpen(window: String, urls: [String])
    case sessionOpen(name: String)
    case extensionsInstall
    case simulator(arguments: [String])
    case topic(TopicInvocation)
    case project(ProjectInvocation)
    case agent(AgentInvocation)
    case window(WindowInvocation)

    static let usage = """
    usage: muxify browser open [--window <id>] <url>...
           muxify session open <session name>
           muxify extensions install
           muxify simulator serve [--port <port>] [--origin <https://host>]
           muxify topic new ["title"] [--project <dir>] [--window <id> | --pane <id>] [--json]
           muxify topic add-project <dir> [--worktree [--base <ref>]] [--topic <id|label> | --window <id> | --pane <id>] [--json]
           muxify topic forget [--remove-worktrees] [--topic <id|label> | --window <id> | --pane <id>] [--json]
           muxify topic settle [--remove-worktrees] [--topic <id|label> | --window <id> | --pane <id>] [--json]
           muxify topic list [--json]
           muxify topic show [--topic <id|label> | --window <id> | --pane <id>] [--json]
           muxify topic status [--project <dir>] [--topic <id|label> | --window <id> | --pane <id>] [--json]
           muxify topic diff [--stat] [--project <dir>] [--topic <id|label> | --window <id> | --pane <id>] [--json]
           muxify topic exec [--project <dir>] [--timeout <seconds>] [--topic <id|label> | --window <id> | --pane <id>] [--json] -- <command> [<argument>...]
           muxify window move --topic <id|label> [--window <id> | --pane <id>] [--json]
           muxify project list [--json]
           muxify agent list [--topic <id|label>] [--status <status>] [--unread] [--json]

    browser open   Opens each URL as a Tab in this tmux Window's Browser.
                     --window <id>   open in another Window instead, e.g. --window @12
    session open   Shows the tmux Session in Muxify. The name may contain spaces,
                   quoted or not: muxify session open my project
    extensions install
                   Installs or updates Extensions for Agents configured under HOME.
    simulator serve  Serves Devices in any browser, independently of the desktop app.
    topic new      Without a title, moves this Pane into an Untitled Topic.
                   With a title, creates a Topic Session and keeps this Pane here.
    topic add-project
                   Adds the Project or Worktree at <dir> to this Pane's Topic.
                     --worktree      start a new Worktree from it on the Topic's branch
                     --base <ref>    start the new Worktree at <ref>, not at HEAD
    topic forget   Removes this Topic for good. --remove-worktrees removes its clean Worktrees.
    topic settle   Settles this Pane's Topic using the default Session choices.
                     --remove-worktrees  also remove each Worktree that the Topic made
                                         and that is merged, as the Settle sheet offers.
                                         If one has uncommitted work, nothing changes.
    topic list     Prints each open Topic's id and label without starting Muxify.
    topic show     Prints this Pane's Topic: its id and label, then a line for each live
                   Session: its name, Project, folder and branch. With --json, also its
                   Windows and Panes, and the Agent, Status and Unread of each Pane.
    topic status   Prints the git status of each live Session of this Pane's Topic, as
                   git status --short --branch does, with each untracked file, under a
                   "==> <session> <==" line.
                   With --json, also each Session's upstream, ahead, behind and base.
                   A Session whose folder is in no repository has "git": null.
                     --project <dir>      only the Session that uses <dir>
    topic diff     Prints one patch of the Topic's work in all its live Sessions. Each
                   path starts with the Session's name. A Session's work is its commits,
                   changes and untracked files since its base: the commit its Worktree
                   started at, else the merge base with origin/HEAD, main or master.
                     --stat               print a summary, not the patch
                     --project <dir>      only the Session that uses <dir>
    topic exec     Runs <command> once in the folder of each live Session of this Pane's
                   Topic, all at the same time, and prints each Session's output under
                   a "==> <session> <==" line. It types nothing into a Pane. It exits
                   with 1 when a run does not exit with 0.
                     --project <dir>      run only in the Session that uses <dir>
                     --timeout <seconds>  stop a run after this time (default 60)
    window move    Moves this Pane's Window, or the Window that --window or --pane
                   names, into the open Topic that --topic names by id or exact label.
    project list   Prints a line for each row of the New Topic list: its folder, its
                   label and the open Topics whose live Sessions use it.
    agent list     Prints a line for each Agent: its Pane, kind, Status, "unread" when it
                   is Unread, and the label of its Topic and the name of its Session.
                     --topic <id|label>  only the Agents in this open Topic
                     --status <status>   only the Agents with this Status: working,
                                         blocked, done or failed
                     --unread            only the Unread Agents

    A Topic command acts on this Pane, or on the target that you name:
                     --topic <id|label>  an open Topic, e.g. --topic "Fix login"
                     --window <id>       a tmux Window, e.g. --window @12
                     --pane <id>         a tmux Pane, e.g. --pane %3
    new, add-project, settle and window move print the id of the Topic that they change.
                     --json              print the full result as one line of JSON

    Optional tmux binding: bind T run-shell 'muxify topic new --pane #{pane_id} >/dev/null'
    """

    init(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        var args = ArraySlice(arguments)
        switch args.popFirst() {
        case "-h", "--help", "help": self = .help
        case "simulator": self = .simulator(arguments: Array(args))
        case "extensions":
            switch args.popFirst() {
            case "-h", "--help": self = .help
            case "install":
                if args.first == "-h" || args.first == "--help" { self = .help; return }
                guard args.isEmpty else { throw CLIError("extensions install takes no arguments") }
                self = .extensionsInstall
            default: throw CLIError(Self.usage, exitCode: 2)
            }
        case "browser":
            switch args.popFirst() {
            case "-h", "--help": self = .help
            case "open": self = try Self.browser(arguments: args, environment: environment)
            default: throw CLIError(Self.usage, exitCode: 2)
            }
        case "topic":
            if args.contains(where: { $0 == "-h" || $0 == "--help" }) { self = .help; return }
            self = .topic(try TopicInvocation(arguments: args, environment: environment))
        case "project":
            if args.contains(where: { $0 == "-h" || $0 == "--help" }) { self = .help; return }
            self = .project(try ProjectInvocation(arguments: args, environment: environment))
        case "window":
            if args.contains(where: { $0 == "-h" || $0 == "--help" }) { self = .help; return }
            self = .window(try WindowInvocation(arguments: args, environment: environment))
        case "agent":
            if args.contains(where: { $0 == "-h" || $0 == "--help" }) { self = .help; return }
            self = .agent(try AgentInvocation(arguments: args, environment: environment))
        case "session":
            switch args.popFirst() {
            case "-h", "--help": self = .help
            case "open":
                if args.first == "-h" || args.first == "--help" { self = .help; return }
                if args.first == "--" { args = args.dropFirst() }
                guard !args.isEmpty else { throw CLIError(Self.usage, exitCode: 2) }
                self = .sessionOpen(name: args.joined(separator: " "))
            default: throw CLIError(Self.usage, exitCode: 2)
            }
        default: throw CLIError(Self.usage, exitCode: 2)
        }
    }

    private static func browser(arguments: ArraySlice<String>, environment: [String: String]) throws -> Self {
        var args = arguments
        var target = ""
        options: while let argument = args.first {
            switch argument {
            case "-w", "--window":
                args = args.dropFirst()
                guard let value = args.popFirst() else { throw CLIError(usage, exitCode: 2) }
                target = value
            case let value where value.hasPrefix("--window="):
                target = String(value.dropFirst("--window=".count))
                args = args.dropFirst()
            case "-h", "--help": return .help
            case "--": args = args.dropFirst(); break options
            case let value where value.hasPrefix("-"): throw CLIError("unknown option \(value)")
            default: break options
            }
        }
        guard !args.isEmpty else { throw CLIError(usage, exitCode: 2) }
        if target.isEmpty {
            guard let pane = environment["TMUX_PANE"], !pane.isEmpty else {
                throw CLIError("not inside tmux; specify the Window with --window <id> (e.g. --window @12)")
            }
            target = pane
        }
        for url in args where url.contains(where: { $0.isWhitespace }) {
            throw CLIError("'\(url)' contains spaces; pass one URL per argument")
        }
        return .browserOpen(window: target, urls: Array(args))
    }

    func execute(using runner: any CLICommandRunning = CLIProcessRunner(),
                 executableURL: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])) async throws {
        switch self {
        case .help: print(Self.usage)
        case .simulator(let arguments): try await SimulatorCommand.serve(arguments: arguments)
        case .extensionsInstall:
            // Installed links point into the app bundle. Resolve them before
            // locating the installer beside its bundled bin directory.
            let installer = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
                .appendingPathComponent("../extensions/install.sh").standardizedFileURL
            guard FileManager.default.isReadableFile(atPath: installer.path) else {
                throw CLIError("Extension installer is missing beside the command line tool")
            }
            let result = try runner.run("/bin/sh", arguments: [installer.path], quiet: false)
            print(result.output, terminator: "")
            try check(result, command: "Extension installer")
        case .browserOpen(let target, let urls):
            // list-panes validates the target; display-message succeeds even for missing Windows.
            let result = try runner.run("tmux", arguments: ["list-panes", "-t", target, "-F", "#{window_id}"], quiet: true)
            let window = result.output.components(separatedBy: "\n").first ?? ""
            guard result.status == 0, !window.isEmpty else { throw CLIError("no tmux Window '\(target)'") }
            // Append so requests made before Muxify's next poll aren't overwritten.
            try check(runner.run("tmux", arguments: ["set-option", "-wa", "-t", window, "@muxify_open", " " + urls.joined(separator: " ")], quiet: false), command: "tmux")
        case .sessionOpen(let name):
            let result = try runner.run("tmux", arguments: ["has-session", "-t", "=\(name)"], quiet: true)
            guard result.status == 0 else { throw CLIError("no tmux session '\(name)'") }
            try open("muxify://select?session=\(Self.percentEncoded(name))", using: runner)
        case .topic(let invocation): try await invocation.run()
        case .project(let invocation): try await invocation.run()
        case .agent(let invocation): try await invocation.run()
        case .window(let invocation): try await invocation.run()
        }
    }

    private func open(_ url: String, using runner: any CLICommandRunning) throws {
        try check(runner.run("open", arguments: [url], quiet: false), command: "open")
    }

    /// Encodes every UTF-8 byte, matching the original CLI's links.
    static func percentEncoded(_ value: String) -> String {
        value.utf8.map { String(format: "%%%02x", $0) }.joined()
    }

    private func check(_ result: CLICommandResult, command: String) throws {
        guard result.status == 0 else { throw CLIError("\(command) exited with status \(result.status)", exitCode: result.status) }
    }
}

struct CLIError: LocalizedError {
    let message: String
    let exitCode: Int32

    init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }

    /// What the Topic service could not do, then how far it got.
    init(_ failure: TopicFailure) {
        self.init("\(failure.message) \(failure.phase.summary)")
    }

    var errorDescription: String? { message }
}
