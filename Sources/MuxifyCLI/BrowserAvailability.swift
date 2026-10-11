import Foundation

enum BrowserAvailability: String {
    case local, remote, no

    var exitCode: Int32 { self == .no ? 1 : 0 }

    static func check(pane: String?, using runner: any CLICommandRunning) -> Self {
        guard let pane, !pane.isEmpty else { return .no }
        func output(_ arguments: [String]) -> String? {
            guard let result = try? runner.run("tmux", arguments: arguments, quiet: true), result.status == 0 else { return nil }
            return result.output
        }
        guard let clients = output(["list-clients", "-t", pane, "-F", "#{client_activity} #{client_control_mode} #{client_pid}"]) else { return .no }
        var newest: Int64 = -1
        var client: String?
        for line in clients.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3, fields[1] == "0", let activity = Int64(fields[0]), activity > newest else { continue }
            newest = activity
            client = fields.dropFirst(2).joined(separator: " ")
        }
        guard let client, let options = output(["show-options", "-s"]) else { return .no }
        for line in options.split(separator: "\n") {
            guard let option = line.split(whereSeparator: \.isWhitespace).first, option.hasPrefix("@muxify_client_"),
                  let marker = output(["show-options", "-sqv", String(option)]) else { continue }
            let fields = marker.trimmingCharacters(in: .newlines).components(separatedBy: "␟")
            guard fields.first == client, let kind = fields.last, let result = Self(rawValue: kind), result != .no else { continue }
            return result
        }
        return .no
    }
}
