import Foundation
import MuxifyCore

/// One `muxify session lock` or `muxify session unlock` command line. It runs the Topic service in this process, so
/// the Lock order is planned with the Topic records under the same locks as every Topic edit (ADR 0010).
struct SessionInvocation: Equatable {
    var locked: Bool
    /// The Session that `--session` names; nil for the caller Pane's Session.
    var target: TopicTarget?
    var caller: PaneID?
    var output: TopicInvocation.Output
    var paths: MuxifyPaths
}

extension SessionInvocation {
    /// Parses the words after `session lock` or `session unlock`. A command line that the command cannot run is a
    /// usage error, status 2.
    init(locked: Bool, arguments: ArraySlice<String>, environment: [String: String]) throws {
        let usageError = CLIError(CLICommand.usage, exitCode: 2)
        var args = arguments
        var name: String?
        var output = TopicInvocation.Output.text
        while let argument = args.popFirst() {
            if argument == "--session" {
                guard name == nil, let value = args.popFirst(), !value.isEmpty else { throw usageError }
                name = value
            } else if argument == "--json" {
                output = .json
            } else {
                throw usageError
            }
        }
        let pane = environment["TMUX_PANE"].flatMap { $0.isEmpty ? nil : $0 }
        let caller = pane.flatMap(PaneID.init(rawValue:))
        if name == nil, caller == nil {
            let problem = pane.map { "TMUX_PANE \($0) is not a tmux Pane id" } ?? "not inside tmux"
            throw CLIError(problem + "; name the Session with --session <name>", exitCode: 2)
        }
        self.init(locked: locked, target: name.map(TopicTarget.sessionName), caller: caller, output: output,
                  paths: MuxifyPaths(environment: environment, home: environment["HOME"] ?? NSHomeDirectory()))
    }

    func run() throws {
        let response = TopicService(paths: paths).handle(TopicRequest(locked ? .lock : .unlock, target: target,
                                                                       caller: caller.map(TopicCaller.pane)))
        try TopicInvocation.report(response, output: output)
    }
}
