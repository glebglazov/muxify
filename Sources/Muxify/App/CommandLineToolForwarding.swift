import Foundation

/// libghostty appends this executable's folder (`Contents/MacOS`) to every
/// terminal's PATH, and macOS volumes are case-insensitive, so `muxify` typed
/// in a Pane can resolve to this app instead of the command line tool. Such
/// runs hand over to the tool bundled at `Contents/Resources/bin/muxify`.
enum CommandLineToolForwarding {
    /// Must run before anything else, while TMUX_PANE is still set.
    static func forwardIfNeeded() {
        guard let tool = Bundle.main.resourceURL?.appendingPathComponent("bin/muxify").path,
              let arguments = toolArguments(for: CommandLine.arguments, tool: tool)
        else { return }
        var argv = arguments.map { strdup($0) } + [nil]
        execv(tool, &argv)
        FileHandle.standardError.write(Data("muxify: can't run \(tool): \(String(cString: strerror(errno)))\n".utf8))
        exit(1)
    }

    /// Launch Services and Xcode start the app by its real name, `Muxify`;
    /// a shell passes the name it looked up on PATH.
    static func toolArguments(for arguments: [String], tool: String) -> [String]? {
        guard let name = arguments.first, (name as NSString).lastPathComponent == "muxify" else { return nil }
        return [tool] + arguments.dropFirst()
    }
}
