import Foundation
import MuxifyCore

/// One `muxify project` command line. `project list` prints the rows of the New Topic list, with the open Topics
/// whose live Sessions use each row. It reads the Config, the Topic records and tmux, and changes nothing.
struct ProjectInvocation: Equatable {
    var output: TopicInvocation.Output
    var paths: MuxifyPaths
}

extension ProjectInvocation {
    /// Parses the words after `project`. A command line that the command cannot run is a usage error, status 2.
    init(arguments: ArraySlice<String>, environment: [String: String]) throws {
        var args = arguments
        guard args.popFirst() == "list" else { throw CLIError(CLICommand.usage, exitCode: 2) }
        var output = TopicInvocation.Output.text
        for argument in args {
            guard argument == "--json" else { throw CLIError(CLICommand.usage, exitCode: 2) }
            output = .json
        }
        self.output = output
        paths = MuxifyPaths(environment: environment, home: environment["HOME"] ?? NSHomeDirectory())
    }

    func run() async throws {
        let projects = try await ConfigProjects.load(paths.configFile).projects
        let records: [TopicRecord]
        do {
            records = try TopicStore(paths: paths).read().records
        } catch {
            throw CLIError("Muxify could not read the Topic records in \(paths.state.path). \(error.localizedDescription)")
        }
        // No tmux server gives no Windows, so no row names a Topic.
        let rows = ProjectRows.build(projects: projects, windows: TmuxServer.local.snapshot().windows, records: records, titles: [:])
        switch output {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(ProjectList(rows: rows)), as: UTF8.self))
        case .text:
            for row in rows {
                print([row.choice.directory.path, row.choice.displayName, row.alsoIn.map(\.label).joined(separator: ", ")]
                    .map(\.oneLineField).joined(separator: "\t"))
            }
        }
    }
}

/// The `--json` form of `project list`.
private struct ProjectList: Encodable {
    struct Entry: Encodable {
        struct Checkout: Encodable {
            let path: String
            let branch: String?

            func encode(to encoder: Encoder) throws {
                var values = encoder.container(keyedBy: CodingKeys.self)
                try values.encode(path, forKey: .path)
                try values.encode(branch, forKey: .branch)
            }

            private enum CodingKeys: String, CodingKey { case path, branch }
        }

        let label: String
        let name: String
        let directory: String
        let project: String
        let worktree: Checkout?
        let topics: [TopicSummary]

        // Synthesized encoding leaves out a nil key. A reader gets every key, with null for no Worktree or branch.
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(label, forKey: .label)
            try values.encode(name, forKey: .name)
            try values.encode(directory, forKey: .directory)
            try values.encode(project, forKey: .project)
            try values.encode(worktree, forKey: .worktree)
            try values.encode(topics, forKey: .topics)
        }

        private enum CodingKeys: String, CodingKey { case label, name, directory, project, worktree, topics }
    }

    let projects: [Entry]

    init(rows: [ProjectRow]) {
        projects = rows.map { row in
            Entry(label: row.choice.displayName, name: row.choice.name, directory: row.choice.directory.path, project: row.choice.project.folder.path,
                  worktree: row.choice.worktree.map { Entry.Checkout(path: $0.folder.path, branch: $0.branch) }, topics: row.alsoIn)
        }
    }
}

extension String {
    /// The value as one field of a tab-separated line: a tab or line break becomes a space.
    var oneLineField: String { replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ") }
}
