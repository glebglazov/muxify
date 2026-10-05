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
    var hasBell: Bool
    var hasActivity: Bool
    let sessionActivity: Int
    var branch: String?

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

/// A client attached to the tmux server (one of them is ours).
struct TmuxClient: Hashable {
    let tty: String
    let sessionID: String
    let windowID: String
}

struct TmuxSnapshot {
    /// Windows of the user's real sessions (Muxify's view sessions excluded).
    var windows: [TmuxWindow]
    var clients: [TmuxClient]
    /// Names of every session on the server, view sessions included.
    var sessionNames: Set<String>
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

    /// Session user option marking the grouped sessions Muxify attaches to.
    static let viewMarker = "@muxify_view"

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
            "#{session_activity}", "#{\(viewMarker)}",
        ].joined(separator: s)
        let clientFormat = ["C", "#{client_tty}", "#{session_id}", "#{window_id}"].joined(separator: s)

        let output: String
        do {
            output = try run(["list-windows", "-a", "-F", windowFormat, ";", "list-clients", "-F", clientFormat])
        } catch {
            return TmuxSnapshot(windows: [], clients: [], sessionNames: [], serverRunning: false)
        }

        var windows: [TmuxWindow] = []
        var clients: [TmuxClient] = []
        var sessionNames = Set<String>()
        // Bell/activity flags are per session; the view session's flags are
        // the ones that reflect what the user has (not) looked at in Muxify.
        var viewFlags: [String: (bell: Bool, activity: Bool)] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: s)
            if f.first == "W", f.count >= 15 {
                sessionNames.insert(f[3])
                if f[14] == "1" {
                    viewFlags[f[1]] = (f[11] == "1", f[12] == "1")
                    continue
                }
                windows.append(TmuxWindow(
                    id: f[1], sessionID: f[2], sessionName: f[3], index: Int(f[4]) ?? 0,
                    name: f[5], paneTitle: f[6], path: f[7], command: f[8],
                    isActive: f[9] == "1", paneCount: Int(f[10]) ?? 1,
                    hasBell: f[11] == "1", hasActivity: f[12] == "1",
                    sessionActivity: Int(f[13]) ?? 0,
                    branch: GitInfo.branch(at: f[7])
                ))
            } else if f.first == "C", f.count >= 4 {
                clients.append(TmuxClient(tty: f[1], sessionID: f[2], windowID: f[3]))
            }
        }
        for i in windows.indices {
            if let flags = viewFlags[windows[i].id] {
                windows[i].hasBell = flags.bell
                windows[i].hasActivity = flags.activity
            }
        }
        return TmuxSnapshot(windows: windows, clients: clients, sessionNames: sessionNames, serverRunning: true)
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
