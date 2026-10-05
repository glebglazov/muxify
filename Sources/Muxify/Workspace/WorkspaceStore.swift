import AppKit
import GhosttyKit
import Observation

struct SessionGroup: Identifiable {
    let id: String
    let name: String
    var windows: [TmuxWindow]
}

/// App state: the tmux windows in the sidebar, the one libghostty surface
/// running our tmux client, and a browser tab per tmux window.
///
/// The terminal is a single `tmux attach` client. Clicking a sidebar window
/// runs `switch-client -c <our tty> -t <window>`, so tmux itself renders the
/// window with all of its splits, and anything you do inside tmux (prefix+n,
/// choose-tree, …) is reflected back into the sidebar selection.
@Observable
final class WorkspaceStore {
    private(set) var windows: [TmuxWindow] = []
    private(set) var serverRunning = true
    private(set) var selectedWindowID: String?
    private(set) var surface: TerminalSurfaceView?
    private(set) var terminalMessage: String?

    var browserVisible = false {
        didSet { UserDefaults.standard.set(browserVisible, forKey: Keys.browserVisible) }
    }

    var selectedWindow: TmuxWindow? {
        guard let selectedWindowID else { return nil }
        return windows.first { $0.id == selectedWindowID }
    }

    var sessions: [SessionGroup] {
        var groups: [SessionGroup] = []
        for window in windows {
            if let last = groups.indices.last, groups[last].id == window.sessionID {
                groups[last].windows.append(window)
            } else {
                groups.append(SessionGroup(id: window.sessionID, name: window.sessionName, windows: [window]))
            }
        }
        return groups
    }

    @ObservationIgnored let terminalHost = TerminalHostView()
    @ObservationIgnored private var browsers: [String: BrowserTab] = [:]
    @ObservationIgnored private var savedURLs: [String: String]
    @ObservationIgnored private var clientTTY: String?
    @ObservationIgnored private var sessionNames = Set<String>()
    @ObservationIgnored private var ownedViews = Set<String>()
    /// A click we sent to tmux that the next snapshots may not reflect yet.
    @ObservationIgnored private var pendingSelection: (windowID: String, deadline: Date)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var started = false

    private enum Keys {
        static let browserVisible = "browserVisible"
        static let browserURLs = "browserURLs"
    }

    init() {
        savedURLs = UserDefaults.standard.dictionary(forKey: Keys.browserURLs) as? [String: String] ?? [:]
        browserVisible = UserDefaults.standard.bool(forKey: Keys.browserVisible)
    }

    func start() {
        guard !started else { return }
        started = true
        GhosttyRuntime.shared.delegate = self
        guard GhosttyRuntime.shared.app != nil else {
            terminalMessage = "libghostty failed to initialize."
            return
        }
        guard Tmux.binary != nil else {
            terminalMessage = "tmux was not found. Install it with `brew install tmux`."
            return
        }
        refresh(attachIfNeeded: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Polling

    func refresh(attachIfNeeded: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = Tmux.snapshot()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.apply(snapshot, attachIfNeeded: attachIfNeeded)
            }
        }
    }

    private func apply(_ snapshot: TmuxSnapshot, attachIfNeeded: Bool) {
        if windows != snapshot.windows { windows = snapshot.windows }
        if serverRunning != snapshot.serverRunning { serverRunning = snapshot.serverRunning }
        sessionNames = snapshot.sessionNames

        if attachIfNeeded, surface == nil {
            attach(to: Self.initialWindow(in: snapshot.windows).map(ViewTarget.init))
            return
        }

        if clientTTY == nil { clientTTY = surface?.ttyName }
        if let tty = clientTTY, let client = snapshot.clients.first(where: { $0.tty == tty }) {
            if let pending = pendingSelection, client.windowID == pending.windowID || Date() > pending.deadline {
                pendingSelection = nil
            }
            if pendingSelection == nil, selectedWindowID != client.windowID {
                selectedWindowID = client.windowID
            }
        } else if surface == nil, let selectedWindowID, !windows.contains(where: { $0.id == selectedWindowID }) {
            self.selectedWindowID = nil
        }

        if snapshot.serverRunning {
            let live = Set(windows.map(\.id))
            browsers = browsers.filter { live.contains($0.key) }
        }
    }

    /// The active window of the most recently used session.
    private static func initialWindow(in windows: [TmuxWindow]) -> TmuxWindow? {
        windows.filter(\.isActive).max { $0.sessionActivity < $1.sessionActivity } ?? windows.first
    }

    // MARK: - View sessions
    //
    // Clients attached to the same tmux session share its current window, so
    // switching windows here would also switch them in every other terminal
    // attached to that session. Instead our client sits in a *grouped* session
    // (`new-session -t <session>`): same windows, independent current window.
    // It is marked with @muxify_view (hidden from the sidebar) and set to
    // destroy-unattached, so tmux removes it as soon as our client leaves it.

    private struct ViewTarget {
        let sessionID: String
        let sessionName: String
        let windowID: String
        let path: String?

        init(_ window: TmuxWindow) {
            self.init(sessionID: window.sessionID, sessionName: window.sessionName, windowID: window.id, path: window.path)
        }

        init(sessionID: String, sessionName: String, windowID: String, path: String?) {
            self.sessionID = sessionID
            self.sessionName = sessionName
            self.windowID = windowID
            self.path = path
        }
    }

    private func viewName(for sessionName: String) -> String {
        let name = "\(sessionName)·muxify"
        // Taken by something we did not create (e.g. another Muxify instance).
        if sessionNames.contains(name), !ownedViews.contains(name) { return "\(name)-\(getpid())" }
        return name
    }

    /// tmux arguments that create the view session for `target` and finish
    /// with our client in it, showing the target window. (Inside one command
    /// list tmux can't resolve `=name` targets for a session created earlier
    /// in that list, so these use plain names.)
    private func createViewArgs(_ target: ViewTarget, view: String, attach: [String]) -> [String] {
        ["new-session", "-d", "-t", target.sessionID, "-s", view,
         ";", "set-option", "-t", view, Tmux.viewMarker, "1",
         ";", "select-window", "-t", "\(view):\(target.windowID)",
         ";"] + attach +
        [";", "set-option", "-t", view, "destroy-unattached", "on"]
    }

    // MARK: - Terminal

    /// Starts our tmux client on `target`, or a fresh session if there is none.
    private func attach(to target: ViewTarget?) {
        let args: [String]
        if let target {
            let view = viewName(for: target.sessionName)
            ownedViews.insert(view)
            args = ["-u"] + createViewArgs(target, view: view, attach: ["attach-session", "-t", view])
        } else {
            args = ["-u", "new-session", "-A", "-s", "main", "-c", NSHomeDirectory()]
        }
        guard let command = Tmux.commandLine(args),
              let view = TerminalSurfaceView(command: command, workingDirectory: target?.path)
        else {
            terminalMessage = "Could not start the terminal."
            return
        }
        surface?.close()
        surface = view
        clientTTY = nil
        terminalMessage = nil
        selectedWindowID = target?.windowID
        if let target { pendingSelection = (target.windowID, Date().addingTimeInterval(3)) }
        terminalHost.show(view)
        focusTerminal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func reattach() {
        attach(to: (selectedWindow ?? Self.initialWindow(in: windows)).map(ViewTarget.init))
    }

    func select(_ window: TmuxWindow) {
        switchClient(to: ViewTarget(window))
    }

    private func switchClient(to target: ViewTarget) {
        selectedWindowID = target.windowID
        pendingSelection = (target.windowID, Date().addingTimeInterval(2))
        focusTerminal()
        guard let surface, !surface.processExited, let tty = clientTTY ?? surface.ttyName else {
            attach(to: target)
            return
        }
        clientTTY = tty
        let view = viewName(for: target.sessionName)
        ownedViews.insert(view)
        let switchArgs = ["switch-client", "-c", tty, "-t", "=\(view):\(target.windowID)"]
        let createArgs = createViewArgs(
            target, view: view, attach: ["switch-client", "-c", tty, "-t", "\(view):\(target.windowID)"]
        )
        // The snapshot can be a second stale, so fall back to the other path.
        let (first, fallback) = sessionNames.contains(view) ? (switchArgs, createArgs) : (createArgs, switchArgs)
        Tmux.runAsync(first) { [weak self] result in
            if case .failure = result {
                Tmux.runAsync(fallback) { _ in self?.refresh() }
            } else {
                self?.refresh()
            }
        }
    }

    func focusTerminal() {
        DispatchQueue.main.async { [weak self] in
            guard let surface = self?.surface else { return }
            surface.window?.makeFirstResponder(surface)
        }
    }

    // MARK: - tmux commands

    func newWindow(inSession sessionID: String? = nil) {
        guard let sessionID = sessionID ?? selectedWindow?.sessionID ?? windows.first?.sessionID,
              let sibling = selectedWindow?.sessionID == sessionID ? selectedWindow : windows.first(where: { $0.sessionID == sessionID })
        else {
            newSession()
            return
        }
        // -d: don't change the window other clients of that session are looking at.
        let args = ["new-window", "-d", "-P", "-F", "#{window_id}", "-t", "\(sessionID):", "-c", sibling.path]
        Tmux.runAsync(args) { [weak self] result in
            guard let self, case .success(let output) = result else { return }
            let windowID = output.trimmingCharacters(in: .whitespacesAndNewlines)
            self.switchClient(to: ViewTarget(
                sessionID: sessionID, sessionName: sibling.sessionName, windowID: windowID, path: sibling.path
            ))
        }
    }

    func newSession() {
        let cwd = selectedWindow?.path ?? NSHomeDirectory()
        var args = ["new-session", "-d", "-P", "-F", "#{session_id}:#{window_id}:#{session_name}", "-c", cwd]
        let name = (cwd as NSString).lastPathComponent.replacingOccurrences(of: ".", with: "_")
        if !name.isEmpty, !sessionNames.contains(name) { args += ["-s", name] }
        Tmux.runAsync(args) { [weak self] result in
            guard let self, case .success(let output) = result else { return }
            let parts = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { return }
            self.switchClient(to: ViewTarget(sessionID: parts[0], sessionName: parts[2], windowID: parts[1], path: cwd))
        }
    }

    func killWindow(_ window: TmuxWindow) {
        Tmux.runAsync(["kill-window", "-t", window.id]) { [weak self] _ in self?.refresh() }
    }

    func renameWindow(_ window: TmuxWindow, to name: String) {
        Tmux.runAsync(["rename-window", "-t", window.id, name]) { [weak self] _ in self?.refresh() }
    }

    /// Runs a tmux command against the pane our client currently has focused.
    private func runOnCurrentPane(_ makeArgs: @escaping (_ paneID: String, _ windowID: String) -> [String]) {
        guard let tty = clientTTY else { return }
        Tmux.runAsync(["display-message", "-p", "-c", tty, "#{pane_id} #{window_id}"]) { [weak self] result in
            guard case .success(let output) = result else { return }
            let ids = output.split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard ids.count == 2 else { return }
            Tmux.runAsync(makeArgs(ids[0], ids[1])) { _ in self?.refresh() }
        }
    }

    // MARK: - Browser

    func browserTab(for windowID: String) -> BrowserTab {
        if let tab = browsers[windowID] { return tab }
        let tab = BrowserTab(windowID: windowID)
        tab.onURLChange = { [weak self] url in
            guard let self else { return }
            self.savedURLs[windowID] = url
            UserDefaults.standard.set(self.savedURLs, forKey: Keys.browserURLs)
        }
        if let saved = savedURLs[windowID], let url = URL(string: saved) { tab.load(url) }
        browsers[windowID] = tab
        return tab
    }

    var currentBrowserTab: BrowserTab? {
        selectedWindowID.map(browserTab(for:))
    }

    func toggleBrowser() {
        browserVisible.toggle()
        if browserVisible {
            if let tab = currentBrowserTab, !tab.hasPage { tab.wantsAddressFocus = true }
        } else {
            focusTerminal()
        }
    }

    func focusAddressBar() {
        browserVisible = true
        currentBrowserTab?.wantsAddressFocus = true
    }

    func openInBrowser(_ url: URL) {
        guard let tab = currentBrowserTab else {
            NSWorkspace.shared.open(url)
            return
        }
        browserVisible = true
        tab.load(url)
    }
}

// MARK: - muxify:// URLs

extension WorkspaceStore {
    /// Scriptable entry points, e.g. from a shell inside tmux:
    ///   open "muxify://open?url=localhost:3000&window=$(tmux display -p '#{window_id}')"
    ///   open "muxify://select?window=@12"
    ///   open "muxify://toggle-browser"
    func handle(_ url: URL) {
        guard url.scheme == "muxify" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        switch url.host {
        case "select":
            if let id = value("window"), let window = windows.first(where: { $0.id == id }) { select(window) }
        case "open":
            guard let input = value("url"), let target = Omnibox.url(for: input) else { return }
            if let id = value("window"), id != selectedWindowID {
                browserTab(for: id).load(target)
            } else {
                openInBrowser(target)
            }
        case "toggle-browser":
            toggleBrowser()
        default:
            NSLog("muxify: unknown URL \(url)")
        }
    }
}

// MARK: - libghostty actions

extension WorkspaceStore: GhosttyRuntimeDelegate {
    func ghosttyOpenURL(_ url: URL) {
        // cmd+click on a link in the terminal opens it in the sidebar browser.
        if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            openInBrowser(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func ghosttyNewTab() { newWindow() }
    func ghosttyNewWindow() { newSession() }

    func ghosttyNewSplit(_ direction: ghostty_action_split_direction_e) {
        let flags: [String]
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_LEFT: flags = ["-h", "-b"]
        case GHOSTTY_SPLIT_DIRECTION_DOWN: flags = ["-v"]
        case GHOSTTY_SPLIT_DIRECTION_UP: flags = ["-v", "-b"]
        default: flags = ["-h"]
        }
        runOnCurrentPane { pane, _ in ["split-window"] + flags + ["-t", pane, "-c", "#{pane_current_path}"] }
    }

    func ghosttyGotoSplit(_ direction: ghostty_action_goto_split_e) {
        switch direction {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: runOnCurrentPane { _, window in ["select-pane", "-t", "\(window).-"] }
        case GHOSTTY_GOTO_SPLIT_NEXT: runOnCurrentPane { _, window in ["select-pane", "-t", "\(window).+"] }
        case GHOSTTY_GOTO_SPLIT_UP: runOnCurrentPane { pane, _ in ["select-pane", "-U", "-t", pane] }
        case GHOSTTY_GOTO_SPLIT_DOWN: runOnCurrentPane { pane, _ in ["select-pane", "-D", "-t", pane] }
        case GHOSTTY_GOTO_SPLIT_LEFT: runOnCurrentPane { pane, _ in ["select-pane", "-L", "-t", pane] }
        default: runOnCurrentPane { pane, _ in ["select-pane", "-R", "-t", pane] }
        }
    }

    func ghosttyToggleSplitZoom() {
        runOnCurrentPane { pane, _ in ["resize-pane", "-Z", "-t", pane] }
    }

    func ghosttyEqualizeSplits() {
        runOnCurrentPane { pane, _ in ["select-layout", "-E", "-t", pane] }
    }

    func ghosttyGotoTab(_ tab: Int32) {
        guard let current = selectedWindow else { return }
        let siblings = windows.filter { $0.sessionID == current.sessionID }
        guard let position = siblings.firstIndex(of: current), !siblings.isEmpty else { return }
        let target: TmuxWindow
        switch tab {
        case GHOSTTY_GOTO_TAB_PREVIOUS.rawValue: target = siblings[(position - 1 + siblings.count) % siblings.count]
        case GHOSTTY_GOTO_TAB_NEXT.rawValue: target = siblings[(position + 1) % siblings.count]
        case GHOSTTY_GOTO_TAB_LAST.rawValue: target = siblings[siblings.count - 1]
        default:
            guard tab >= 1, Int(tab) <= siblings.count else { return }
            target = siblings[Int(tab) - 1]
        }
        select(target)
    }

    func ghosttySurfaceClosed(_ view: TerminalSurfaceView) {
        guard view === surface else {
            view.close()
            return
        }
        // A close request (e.g. cmd+w) while tmux is still attached: keep the client.
        guard view.processExited else { return }
        view.close()
        surface = nil
        clientTTY = nil
        terminalHost.show(nil)
        refresh()
    }
}

/// Plain AppKit container the SwiftUI layout embeds; the terminal surface view
/// is swapped in and out of it without SwiftUI recreating anything.
final class TerminalHostView: NSView {
    private weak var current: NSView?

    func show(_ view: NSView?) {
        current?.removeFromSuperview()
        current = view
        guard let view else { return }
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}
