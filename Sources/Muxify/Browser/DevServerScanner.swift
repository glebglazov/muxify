import Foundation

/// Finds TCP ports that processes running inside a tmux window are listening
/// on, so the browser can offer "open localhost:3000" for that window.
enum DevServerScanner {
    private static let queue = DispatchQueue(label: "muxify.ports", qos: .utility)

    static func scan(windowID: String, completion: @escaping ([Int]) -> Void) {
        queue.async {
            let ports = listeningPorts(windowID: windowID)
            DispatchQueue.main.async { completion(ports) }
        }
    }

    private static func listeningPorts(windowID: String) -> [Int] {
        guard let paneOutput = try? Tmux.run(["list-panes", "-t", windowID, "-F", "#{pane_pid}"]) else { return [] }
        let roots = paneOutput.split(separator: "\n").compactMap { Int32($0) }
        guard !roots.isEmpty else { return [] }

        // Every descendant of the window's pane processes.
        guard let psOutput = try? Shell.run("/bin/ps", ["-axo", "pid=,ppid="]) else { return [] }
        var children: [Int32: [Int32]] = [:]
        for line in psOutput.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            children[ppid, default: []].append(pid)
        }
        var pids = Set(roots)
        var stack = roots
        while let pid = stack.popLast() {
            for child in children[pid] ?? [] where pids.insert(child).inserted {
                stack.append(child)
            }
        }

        // lsof exits non-zero when nothing matches; treat that as "no ports".
        guard let lsofOutput = try? Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]) else { return [] }
        var ports = Set<Int>()
        var currentPID: Int32 = 0
        for line in lsofOutput.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPID = Int32(line.dropFirst()) ?? 0
            } else if line.hasPrefix("n"), pids.contains(currentPID),
                      let colon = line.lastIndex(of: ":"),
                      let port = Int(line[line.index(after: colon)...]) {
                ports.insert(port)
            }
        }
        return ports.sorted()
    }
}
