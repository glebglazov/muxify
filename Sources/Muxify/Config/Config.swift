import Foundation
import Yams

/// A Config value that could not apply, or the syntax error that stopped the
/// whole file from applying.
struct ConfigProblem: Equatable, CustomStringConvertible {
    let path: String
    let line: Int
    let message: String

    var description: String { "\(path):\(line): \(message)" }
}

/// A Config file that is not valid YAML. Nothing in it applies.
struct ConfigSyntaxError: Error, Equatable {
    let problem: ConfigProblem
}

/// The Config: how Muxify itself behaves, read from a YAML file.
struct Config: Equatable {
    var keybinds = Keybinds.defaults
    /// The Ghostty config file the terminal loads on top of Ghostty's
    /// default files, as an absolute path.
    var ghosttyConfigFile: String?
    var problems: [ConfigProblem] = []

    static var defaultPath: String {
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(NSHomeDirectory())/.config"
        return "\(xdg)/muxify/config.yaml"
    }

    /// Reads the Config at `path`. A missing file gives the defaults. A value
    /// that cannot apply is skipped and recorded in `problems`; a syntax error
    /// fails the whole read.
    static func load(path: String, read: (String) -> String?) -> Result<Config, ConfigSyntaxError> {
        guard let text = read(path) else { return .success(Config()) }
        let root: Node?
        do {
            root = try Yams.compose(yaml: text)
        } catch {
            return .failure(ConfigSyntaxError(path: path, error))
        }
        guard let root else { return .success(Config()) }
        return withoutActuallyEscaping(read) { read in
            var reader = ConfigReader(path: path, read: read)
            reader.readSections(root)
            return .success(reader.config)
        }
    }

    /// What Open Config writes into a new Config file.
    static var template: String {
        let defaults = Keybinds.defaultSpelling.map { action, spellings in
            "#   \(action.rawValue): \(spellings.count == 1 ? spellings[0] : "[\(spellings.joined(separator: ", "))]")"
        }
        return """
        # Muxify Config. Muxify reloads it when it changes.
        #
        # ghostty:
        #   # The Ghostty config the terminal loads after Ghostty's default
        #   # files. ~/ is the home directory; a relative path starts at the
        #   # directory of this file.
        #   config_file: ~/.config/ghostty/config
        #
        # keybindings:
        #   # An action maps to one trigger or a list of them, spelled as in
        #   # Ghostty. Naming an action replaces its defaults, and [] leaves it
        #   # with no keybinding. A trigger listed here is taken from the
        #   # defaults of other actions. The defaults:
        \(defaults.joined(separator: "\n"))

        """
    }
}

/// What Muxify runs with: the last Config that read without a syntax error,
/// and the problems of the latest read. A half-typed edit shows its syntax
/// error but does not reset the keybinds in use.
struct LoadedConfig: Equatable {
    private(set) var config = Config()
    private(set) var problems: [ConfigProblem] = []

    mutating func update(with result: Result<Config, ConfigSyntaxError>) {
        switch result {
        case .success(let config):
            self.config = config
            problems = config.problems
        case .failure(let error):
            problems = [error.problem]
        }
    }
}

private extension ConfigSyntaxError {
    init(path: String, _ error: Error) {
        switch error as? YamlError {
        case let .scanner(context, message, mark, _), let .parser(context, message, mark, _), let .composer(context, message, mark, _):
            let text = [context?.text, message].compactMap { $0 }.joined(separator: ": ")
            problem = ConfigProblem(path: path, line: mark.line, message: text)
        case let .duplicatedKeysInMapping(duplicates, context):
            problem = ConfigProblem(path: path, line: context.mark.line, message: "duplicate key \(duplicates.joined(separator: ", "))")
        default:
            problem = ConfigProblem(path: path, line: 1, message: "\(error)")
        }
    }
}

/// Turns the YAML nodes of one Config file into a Config, skipping what
/// cannot apply.
private struct ConfigReader {
    let path: String
    let read: (String) -> String?
    var config = Config()

    static let sections: [String: (inout ConfigReader, Node) -> Void] = [
        "ghostty": { $0.readGhostty($1) },
        "keybindings": { $0.readKeybindings($1) },
    ]

    mutating func readSections(_ root: Node) {
        for (name, key, value) in entries(of: root, "the Config") {
            guard let section = Self.sections[name] else {
                problem(at: key, "unknown section \"\(name)\"")
                continue
            }
            section(&self, value)
        }
    }

    mutating func readGhostty(_ node: Node) {
        for (name, key, value) in entries(of: node, "ghostty") {
            switch name {
            case "config_file":
                guard let path = string(value) else {
                    problem(at: value, "ghostty.config_file: expected a path")
                    continue
                }
                let file = ConfigFileSet.resolve(path, relativeTo: (self.path as NSString).deletingLastPathComponent)
                // Kept although missing, so the watcher sees the file appear.
                config.ghosttyConfigFile = file
                if read(file) == nil { problem(at: value, "ghostty.config_file \(file): not found") }
            default:
                problem(at: key, "unknown key \"ghostty.\(name)\"")
            }
        }
    }

    mutating func readKeybindings(_ node: Node) {
        var named: [(action: ConfigAction, listed: [(trigger: KeyTrigger, node: Node)])] = []
        for (name, key, value) in entries(of: node, "keybindings") {
            guard let action = ConfigAction(rawValue: name) else {
                problem(at: key, "unknown action \"\(name)\"")
                continue
            }
            if let listed = triggers(in: value, of: action) { named.append((action, listed)) }
        }
        config.keybinds = overlay(named)
    }

    /// The overlay rules. An action the user named has only the triggers
    /// listed for it. An action not named keeps its defaults, minus any
    /// trigger listed for another action. A trigger listed under two actions
    /// stays with the first.
    private mutating func overlay(_ named: [(action: ConfigAction, listed: [(trigger: KeyTrigger, node: Node)])]) -> Keybinds {
        var owners: [KeyTrigger: ConfigAction] = [:]
        var triggers: [ConfigAction: [KeyTrigger]] = [:]
        for (action, listed) in named {
            var kept: [KeyTrigger] = []
            for (trigger, node) in listed {
                switch owners[trigger] {
                case nil:
                    owners[trigger] = action
                    kept.append(trigger)
                case action?:
                    continue
                case let owner?:
                    problem(at: node, "\(node.string ?? "") is already bound to \(owner.rawValue)")
                }
            }
            triggers[action] = kept
        }
        for action in ConfigAction.allCases where triggers[action] == nil {
            triggers[action] = Keybinds.defaults.triggers[action, default: []].filter { owners[$0] == nil }
        }
        return Keybinds(triggers: triggers)
    }

    /// One trigger or a list of them. A bad item of a list is skipped; a bad
    /// single value skips the action, so it keeps its defaults.
    private mutating func triggers(in node: Node, of action: ConfigAction) -> [(trigger: KeyTrigger, node: Node)]? {
        if let sequence = node.sequence {
            return sequence.compactMap { trigger(in: $0, of: action) }
        }
        return trigger(in: node, of: action).map { [$0] }
    }

    private mutating func trigger(in node: Node, of action: ConfigAction) -> (trigger: KeyTrigger, node: Node)? {
        guard let spelling = string(node) else {
            problem(at: node, "\(action.rawValue): expected a trigger or a list of triggers")
            return nil
        }
        do {
            return (try KeyTrigger(spelling), node)
        } catch {
            problem(at: node, "\(error)")
            return nil
        }
    }

    private mutating func entries(of node: Node, _ place: String) -> [(name: String, key: Node, value: Node)] {
        guard let mapping = node.mapping else {
            problem(at: node, "\(place): expected a mapping")
            return []
        }
        return mapping.map { ($0.key.string ?? "", $0.key, $0.value) }
    }

    /// A scalar other than null (empty, `~` or `null`).
    private func string(_ node: Node) -> String? {
        guard let scalar = node.scalar, node.null == nil else { return nil }
        return scalar.string
    }

    private mutating func problem(at node: Node, _ message: String) {
        config.problems.append(ConfigProblem(path: path, line: node.mark?.line ?? 1, message: message))
    }
}
