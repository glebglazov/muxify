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
            CommandGroup(replacing: .sidebar) {
                Button(store.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { store.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            // Browser shortcuts act only when focus is outside the terminal;
            // in the terminal your Ghostty/tmux bindings handle the keys.
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { store.browserCommand { $0.newTab() } }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New tmux Window") { store.newWindow() }
                Button("New tmux Session") { store.newSession() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Browser") {
                Button(store.currentBrowser?.isOpen == true ? "Hide Browser" : "Show Browser") { store.toggleBrowser() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Open Location…") { store.browserCommand { _ in store.focusAddressBar() } }
                    .keyboardShortcut("l", modifiers: .command)
                Divider()
                Button("Close Tab") { store.browserCommand { $0.closeActiveTab() } }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Show Next Tab") { store.browserCommand { $0.selectTab(offset: 1) } }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Show Previous Tab") { store.browserCommand { $0.selectTab(offset: -1) } }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                Button("Back") { store.browserCommand { $0.activeTab?.goBack() } }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Forward") { store.browserCommand { $0.activeTab?.goForward() } }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Reload Page") { store.browserCommand { $0.activeTab?.reloadOrStop() } }
                    .keyboardShortcut("r", modifiers: .command)
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
