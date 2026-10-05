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
    let hasActivity: Bool
    let sessionActivity: Int
    var branch: String?
    /// The Window's Browser as last written to its tmux options.
    var storedBrowser: StoredBrowser
    /// URLs a program asked to open via `@muxify_open` (not yet consumed).
    var openRequests: [String]

    /// The pane title is what shells and TUIs set via OSC 0/2 (fish sets it to
    /// `~/w/project`), so it is the best human label. tmux defaults it to the
    /// hostname, in which case we fall back to the window name or the path.
    var displayTitle: String {
        let title = paneTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty, title != Tmux.hostName, title != Tmux.shortHostName {
            return title
        }
        if !Tmux.shellNames.contains(name) { return name }
        return Paths.fishStyle(path)
    }

    var abbreviatedPath: String { Paths.tildify(path) }
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

struct TmuxSnapshot {
    var windows: [TmuxWindow]
    var clients: [TmuxClient]
    /// The Window last selected in Muxify (a server-wide option, so it can't
    /// outlive the server and point at a reused window id).
    var lastWindowID: String?
    var serverRunning: Bool
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

    /// One round trip that lists every window on the server and every client.
    static func snapshot() -> TmuxSnapshot {
        let s = separator
        let windowFormat = [
            "W", "#{window_id}", "#{session_id}", "#{session_name}", "#{window_index}",
            "#{window_name}", "#{pane_title}", "#{pane_current_path}", "#{pane_current_command}",
            "#{window_active}", "#{window_panes}", "#{window_bell_flag}", "#{window_activity_flag}",
            "#{session_activity}",
            "#{\(tabsOption)}", "#{\(activeTabOption)}", "#{\(browserOpenOption)}", "#{\(openOption)}",
            "#{\(lastWindowOption)}",
        ].joined(separator: s)
        let clientFormat = ["C", "#{client_tty}", "#{session_id}", "#{window_id}"].joined(separator: s)

        let output: String
        do {
            output = try run(["list-windows", "-a", "-F", windowFormat, ";", "list-clients", "-F", clientFormat])
        } catch {
            return TmuxSnapshot(windows: [], clients: [], lastWindowID: nil, serverRunning: false)
        }

        var windows: [TmuxWindow] = []
        var clients: [TmuxClient] = []
        var lastWindowID: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: s)
            if f.first == "W", f.count >= 19 {
                windows.append(TmuxWindow(
                    id: f[1], sessionID: f[2], sessionName: f[3], index: Int(f[4]) ?? 0,
                    name: f[5], paneTitle: f[6], path: f[7], command: f[8],
                    isActive: f[9] == "1", paneCount: Int(f[10]) ?? 1,
                    hasBell: f[11] == "1", hasActivity: f[12] == "1",
                    sessionActivity: Int(f[13]) ?? 0,
                    branch: GitInfo.branch(at: f[7]),
                    storedBrowser: StoredBrowser(tabs: f[14], activeTab: f[15], open: f[16]),
                    openRequests: f[17].split(separator: " ").map(String.init)
                ))
                if !f[18].isEmpty { lastWindowID = f[18] }
            } else if f.first == "C", f.count >= 4 {
                clients.append(TmuxClient(tty: f[1], sessionID: f[2], windowID: f[3]))
            }
        }
        return TmuxSnapshot(windows: windows, clients: clients, lastWindowID: lastWindowID, serverRunning: true)
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
