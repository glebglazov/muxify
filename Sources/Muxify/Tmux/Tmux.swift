import Foundation

/// A tmux window as shown in the sidebar.
struct TmuxWindow: Identifiable, Hashable {
    /// Server-unique window id, e.g. "@27".
    let id: String
    let sessionID: String
    let sessionName: String
    let index: Int
    let name: String
    let paneTitle: String
    let path: String
    let command: String
    let isActive: Bool
    let paneCount: Int
    let hasBell: Bool
    let sessionActivity: Int
    /// The active Pane's `@muxify_agent`, empty when no Agent reports there.
    let agent: String
    /// The Window's Browser as last written to its tmux options.
    var storedBrowser: StoredBrowser
    /// URLs a program asked to open via `@muxify_open` (not yet consumed).
    var openRequests: [String]

    /// The pane title is what shells and TUIs set via OSC 0/2 (fish sets it to
    /// `~/w/project`), so it is the best human label. tmux defaults it to the
    /// hostname, in which case we fall back to the window name or the path.
    var displayTitle: String {
        let title = Self.withoutLeadingGlyph(paneTitle.trimmingCharacters(in: .whitespaces))
        if !title.isEmpty, title != Tmux.hostName, title != Tmux.shortHostName {
            return title
        }
        if !Tmux.shellNames.contains(name) { return name }
        return Paths.fishStyle(path)
    }

    var abbreviatedPath: String { Paths.tildify(path) }

    /// The logo for what the active Pane runs (`Resources/Logos`): the Agent
    /// it reports, else its command. Claude Code shows up as its version
    /// number (`2.1.289`) until its Extension reports. A command's version
    /// suffix and case don't matter (`python3.12`, `Python` → `python`).
    /// Shells get the terminal logo.
    var logoName: String {
        if AgentKind(rawValue: agent) != nil { return agent }
        if Tmux.shellNames.contains(command) { return "terminal" }
        if command.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil { return AgentKind.claude.rawValue }
        if let alias = Self.commandAliases[command] { return alias }
        let name = command.lowercased().replacingOccurrences(of: #"[\d.]+$"#, with: "", options: .regularExpression)
        return Self.commandAliases[name] ?? (name.isEmpty ? command : name)
    }

    /// Commands that share another command's logo.
    private static let commandAliases = [
        "vim": "nvim", "vi": "nvim",
        "cargo": "rust", "rustc": "rust",
        "postgres": "psql",
        "redis-cli": "redis", "redis-server": "redis",
    ]

    /// Claude Code titles its terminal "✳ <conversation>" and animates the
    /// glyph while it works; the logo already says it's Claude.
    private static func withoutLeadingGlyph(_ title: String) -> String {
        let scalars = title.unicodeScalars.drop { $0.properties.generalCategory == .otherSymbol || $0 == "·" }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? title : text
    }
}

/// A Window's Browser as stored in tmux window options (ADR 0003). Tab URLs
/// are space-separated (URLs never contain spaces); an empty Tab is
/// `about:blank`.
struct StoredBrowser: Hashable {
    var tabURLs: [String] = []
    var activeTab = 0
    var isOpen = false

    init(tabURLs: [String] = [], activeTab: Int = 0, isOpen: Bool = false) {
        self.tabURLs = tabURLs
        self.activeTab = activeTab
        self.isOpen = isOpen
    }

    init(tabs: String, activeTab: String, open: String) {
        tabURLs = tabs.split(separator: " ").map(String.init)
        self.activeTab = Int(activeTab) ?? 0
        isOpen = open == "on"
    }

    /// `set-option` arguments that write this state onto `windowID`.
    func setOptionArgs(windowID: String) -> [String] {
        guard !tabURLs.isEmpty else {
            return Array([Tmux.tabsOption, Tmux.activeTabOption, Tmux.browserOpenOption].flatMap {
                ["set-option", "-wqu", "-t", windowID, $0, ";"]
            }.dropLast())
        }
        return ["set-option", "-wq", "-t", windowID, Tmux.tabsOption, tabURLs.joined(separator: " "),
                ";", "set-option", "-wq", "-t", windowID, Tmux.activeTabOption, String(activeTab),
                ";", "set-option", "-wq", "-t", windowID, Tmux.browserOpenOption, isOpen ? "on" : "off"]
    }
}

/// A client attached to the tmux server (one of them is ours).
struct TmuxClient: Hashable {
    let tty: String
    let sessionID: String
    let windowID: String
}

/// A tmux Pane, with the options an Agent's Extension writes onto it (ADR 0004).
struct TmuxPane: Hashable {
    /// Server-unique pane id, e.g. "%42".
    let id: String
    let windowID: String
    /// `#{pane_current_command}`. It can't identify an Agent (Claude Code's is
    /// its version number), but a plain shell here means no Agent is running.
    let command: String
    /// `@muxify_agent`, empty when unset.
    let agent: String
    /// `@muxify_agent_status`, empty when unset.
    let agentStatus: String
    /// `@muxify_agent_unread`, which Muxify itself sets.
    let unread: Bool
}

struct TmuxSnapshot {
    var windows: [TmuxWindow]
    var clients: [TmuxClient]
    var panes: [TmuxPane]
    /// The Window last selected in Muxify (a server-wide option, so it can't
    /// outlive the server and point at a reused window id).
    var lastWindowID: String?
    var serverRunning: Bool

    /// The Agents running in this snapshot's Panes, in tmux order.
    var agents: [Agent] { Agent.list(panes: panes, windows: windows) }
}

enum TmuxError: Error, CustomStringConvertible {
    case notInstalled
    case failed(status: Int32, stderr: String)

    var description: String {
        switch self {
        case .notInstalled: return "tmux was not found on this Mac"
        case .failed(let status, let stderr): return "tmux exited with \(status): \(stderr)"
        }
    }
}

enum Tmux {
    static let binary: String? = locateBinary()
    static let hostName = ProcessInfo.processInfo.hostName
    static let shortHostName = hostName.split(separator: ".").first.map(String.init) ?? hostName
    static let shellNames: Set<String> = ["fish", "zsh", "bash", "sh", "nu", "elvish", "xonsh", "login"]

    // tmux user options Muxify keeps its state in.
    static let tabsOption = "@muxify_tabs"
    static let activeTabOption = "@muxify_active_tab"
    static let browserOpenOption = "@muxify_browser"
    /// One-shot: programs set it to open a Tab; Muxify consumes and clears it.
    static let openOption = "@muxify_open"
    static let lastWindowOption = "@muxify_last_window"
    // Pane options an Agent's Extension writes (ADR 0004).
    static let agentOption = "@muxify_agent"
    static let agentStatusOption = "@muxify_agent_status"
    /// Set by Muxify, not the Extension: the Agent finished or got blocked
    /// while you weren't looking at its Window.
    static let agentUnreadOption = "@muxify_agent_unread"

    private static let queue = DispatchQueue(label: "muxify.tmux", qos: .userInitiated)
    private static let separator = "\u{241F}"

    private static func locateBinary() -> String? {
        var candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/run/current-system/sw/bin/tmux",
            "\(NSHomeDirectory())/.nix-profile/bin/tmux",
            "/usr/bin/tmux",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/tmux" }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Shell command line that runs tmux with the given arguments. Used as the
    /// libghostty surface command, which is executed through `/bin/sh -c`.
    static func commandLine(_ args: [String]) -> String? {
        guard let binary else { return nil }
        return ([binary] + args).map(shellQuote).joined(separator: " ")
    }

    @discardableResult
    static func run(_ args: [String]) throws -> String {
        guard let binary else { throw TmuxError.notInstalled }
        return try Shell.run(binary, args)
    }

    /// Runs tmux commands off the main thread, in order, and calls back on main.
    static func runAsync(_ args: [String], completion: ((Result<String, Error>) -> Void)? = nil) {
        queue.async {
            let result = Result { try run(args) }
            if case .failure(let error) = result {
                NSLog("muxify: tmux \(args.joined(separator: " ")) failed: \(error)")
            }
            if let completion {
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// One round trip that lists every window on the server, every client and
    /// every pane (for the Agents in them).
    static func snapshot() -> TmuxSnapshot {
        let s = separator
        let windowFormat = [
            "W", "#{window_id}", "#{session_id}", "#{session_name}", "#{window_index}",
            "#{window_name}", "#{pane_title}", "#{pane_current_path}", "#{pane_current_command}",
            "#{window_active}", "#{window_panes}", "#{window_bell_flag}", "#{session_activity}",
            "#{\(tabsOption)}", "#{\(activeTabOption)}", "#{\(browserOpenOption)}", "#{\(openOption)}",
            "#{\(lastWindowOption)}", "#{\(agentOption)}",
        ].joined(separator: s)
        let clientFormat = ["C", "#{client_tty}", "#{session_id}", "#{window_id}"].joined(separator: s)
        let paneFormat = [
            "P", "#{pane_id}", "#{window_id}", "#{pane_current_command}",
            "#{\(agentOption)}", "#{\(agentStatusOption)}", "#{\(agentUnreadOption)}",
        ].joined(separator: s)

        let output: String
        do {
            output = try run([
                "list-windows", "-a", "-F", windowFormat,
                ";", "list-clients", "-F", clientFormat,
                ";", "list-panes", "-a", "-F", paneFormat,
            ])
        } catch {
            return TmuxSnapshot(windows: [], clients: [], panes: [], lastWindowID: nil, serverRunning: false)
        }

        var windows: [TmuxWindow] = []
        var clients: [TmuxClient] = []
        var panes: [TmuxPane] = []
        var lastWindowID: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: s)
            if f.first == "W", f.count >= 19 {
                windows.append(TmuxWindow(
                    id: f[1], sessionID: f[2], sessionName: f[3], index: Int(f[4]) ?? 0,
                    name: f[5], paneTitle: f[6], path: f[7], command: f[8],
                    isActive: f[9] == "1", paneCount: Int(f[10]) ?? 1,
                    hasBell: f[11] == "1",
                    sessionActivity: Int(f[12]) ?? 0,
                    agent: f[18],
                    storedBrowser: StoredBrowser(tabs: f[13], activeTab: f[14], open: f[15]),
                    openRequests: f[16].split(separator: " ").map(String.init)
                ))
                if !f[17].isEmpty { lastWindowID = f[17] }
            } else if f.first == "C", f.count >= 4 {
                clients.append(TmuxClient(tty: f[1], sessionID: f[2], windowID: f[3]))
            } else if f.first == "P", f.count >= 7 {
                panes.append(TmuxPane(
                    id: f[1], windowID: f[2], command: f[3],
                    agent: f[4], agentStatus: f[5], unread: f[6] == "1"
                ))
            }
        }
        return TmuxSnapshot(
            windows: windows, clients: clients, panes: panes,
            lastWindowID: lastWindowID, serverRunning: true
        )
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum Shell {
    /// Runs a program synchronously and returns stdout. Throws on non-zero exit.
    static func run(_ executable: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TmuxError.failed(
                status: process.terminationStatus,
                stderr: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return String(decoding: out, as: UTF8.self)
    }
}

enum Paths {
    static let home = NSHomeDirectory()

    /// `/Users/me/work/app` -> `~/work/app`
    static func tildify(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// fish's `prompt_pwd`: `/Users/me/work/app` -> `~/w/app`
    static func fishStyle(_ path: String) -> String {
        let parts = tildify(path).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return tildify(path) }
        let shortened = parts.enumerated().map { index, part -> String in
            if index == parts.count - 1 || part.isEmpty || part == "~" { return String(part) }
            let prefixLength = part.hasPrefix(".") ? 2 : 1
            return String(part.prefix(prefixLength))
        }
        return shortened.joined(separator: "/")
    }
}
