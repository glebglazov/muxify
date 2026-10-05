import Foundation

/// Hears about tmux changes as they happen through a control-mode client
/// (`tmux -C`), so the sidebar doesn't wait for the next poll when a Window is
/// switched, added, closed or renamed. The client only listens: it is
/// read-only, gets no pane output and doesn't count towards window sizes.
final class TmuxEvents {
    enum Event {
        /// A Session's current Window changed (select-window, prefix+n, …).
        case sessionWindowChanged(sessionID: String, windowID: String)
        /// Anything else that may change what the sidebar shows.
        case other
    }

    /// Called on the main thread.
    var onEvent: ((Event) -> Void)?

    private var process: Process?
    private var input: Pipe?
    /// Output not yet split into lines; only touched by the read handler.
    private var buffer = Data()

    var isRunning: Bool { process?.isRunning == true }

    /// Attaches to `sessionID`. Notifications cover every Session, so which
    /// one doesn't matter.
    func start(sessionID: String) {
        guard !isRunning, let binary = Tmux.binary else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-C", "attach-session", "-f", "read-only,no-output,ignore-size", "-t", sessionID]
        // Control mode exits when its input closes, so holding the pipe keeps
        // it running, and it goes away with us even if we crash.
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        buffer.removeAll()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.received(data)
        }
        do {
            try process.run()
        } catch {
            NSLog("muxify: tmux control client failed to start: \(error)")
            return
        }
        self.process = process
        self.input = input
    }

    private func received(_ data: Data) {
        buffer.append(data)
        var events: [Event] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = Self.event(from: line) { events.append(event) }
        }
        guard !events.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            events.forEach { self?.onEvent?($0) }
        }
    }

    private static func event(from line: String) -> Event? {
        let words = line.split(separator: " ")
        guard let kind = words.first, kind.hasPrefix("%") else { return nil }
        switch kind {
        case "%begin", "%end", "%error", "%output", "%extended-output", "%exit":
            return nil
        case "%session-window-changed" where words.count >= 3:
            return .sessionWindowChanged(sessionID: String(words[1]), windowID: String(words[2]))
        default:
            return .other
        }
    }
}
