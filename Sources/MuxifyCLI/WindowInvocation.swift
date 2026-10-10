import Foundation
import MuxifyCore

/// One `muxify window` command line. `window move` moves a Window into an open Topic with the same plan as
/// Move, through the Topic service in this process. The service chooses the Window: `target`, else `caller`'s.
struct WindowInvocation: Equatable {
    /// The open Topic to move to, by id or label.
    var topic: String
    /// A `.window` or `.pane` target.
    var target: TopicTarget?
    var caller: PaneID?
    var output: TopicInvocation.Output
    var paths: MuxifyPaths
}

extension WindowInvocation {
    /// Parses the words after `window`. A command line that the command cannot run is a usage error, status 2.
    init(arguments: ArraySlice<String>, environment: [String: String]) throws {
        let usageError = CLIError(CLICommand.usage, exitCode: 2)
        var args = arguments
        guard args.popFirst() == "move" else { throw usageError }
        var topic: String?
        var targets = TopicInvocation.TargetOptions(accepting: [.window, .pane])
        var output = TopicInvocation.Output.text
        while let argument = args.popFirst() {
            if try targets.take(argument, from: &args) {
                continue
            } else if argument == "--topic" {
                guard topic == nil, let value = args.popFirst() else { throw usageError }
                topic = try TopicInvocation.TargetOption.topicName(value)
            } else if argument == "--json" {
                output = .json
            } else {
                throw usageError
            }
        }
        guard let topic else { throw CLIError("window move takes the Topic to move to: --topic <id|label>", exitCode: 2) }
        let caller = try targets.caller(environment: environment, needed: true, offered: targets.accepted)
        self.init(topic: topic, target: targets.chosen?.target, caller: caller, output: output,
                  paths: MuxifyPaths(environment: environment, home: environment["HOME"] ?? NSHomeDirectory()))
    }

    func run() async throws {
        let config = try await ConfigProjects.load(paths.configFile)
        // No client: no terminal switches to the moved Window.
        let response = TopicService(paths: paths, server: .local, projects: config.projects, sessionOrder: config.topics.sessionOrder)
            .handle(TopicRequest(.move(to: .topic(.named(topic))), target: target, caller: caller.map(TopicCaller.pane)))
        try TopicInvocation.report(response, output: output)
    }
}
