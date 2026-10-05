import AppKit
import SwiftUI

@main
struct MuxifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: WorkspaceStore

    init() {
        AppEnvironment.prepare()
        GhosttyRuntime.shared.start()
        _store = State(initialValue: WorkspaceStore())
    }

    var body: some Scene {
        Window("Muxify", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 820, minHeight: 480)
        }
        .defaultSize(width: 1500, height: 920)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New tmux Window") { store.newWindow() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New tmux Session") { store.newSession() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Browser") {
                Button(store.browserVisible ? "Hide Browser" : "Show Browser") { store.toggleBrowser() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Open Location…") { store.focusAddressBar() }
                    .keyboardShortcut("l", modifiers: .command)
                Divider()
                Button("Back") { store.currentBrowserTab?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!store.browserVisible)
                Button("Forward") { store.currentBrowserTab?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!store.browserVisible)
                Button("Reload Page") { store.currentBrowserTab?.reloadOrStop() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!store.browserVisible)
                Divider()
                Button("Focus Terminal") { store.focusTerminal() }
                    .keyboardShortcut("`", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("Reload Ghostty Config") { GhosttyRuntime.shared.reloadConfig() }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum AppEnvironment {
    /// Process environment fixes that must happen before libghostty and the
    /// first tmux invocation, since both are inherited by child processes.
    static func prepare() {
        // Launched from inside tmux (e.g. `open` in a pane), tmux refuses to nest.
        unsetenv("TMUX")
        unsetenv("TMUX_PANE")

        // Finder-launched apps get no locale; tmux then draws Unicode as `_`.
        if getenv("LANG") == nil { setenv("LANG", "en_US.UTF-8", 1) }

        // Finder-launched apps get a minimal PATH; make Homebrew tools visible.
        var path = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        for dir in ["/usr/local/bin", "/opt/homebrew/sbin", "/opt/homebrew/bin"] where !path.contains(dir) {
            path.insert(dir, at: 0)
        }
        setenv("PATH", path.joined(separator: ":"), 1)

        // libghostty finds terminfo/themes inside our bundle (copied at build
        // time). If they are missing, borrow them from an installed Ghostty.app.
        let fm = FileManager.default
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("terminfo/78/xterm-ghostty").path ?? ""
        let installed = "/Applications/Ghostty.app/Contents/Resources/ghostty"
        if !fm.fileExists(atPath: bundled), getenv("GHOSTTY_RESOURCES_DIR") == nil, fm.fileExists(atPath: installed) {
            setenv("GHOSTTY_RESOURCES_DIR", installed, 1)
        }
    }
}
