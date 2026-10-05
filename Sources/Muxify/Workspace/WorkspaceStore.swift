import AppKit
import GhosttyKit
import Observation

struct SessionGroup: Identifiable {
    let id: String
    let name: String
    var windows: [TmuxWindow]
}

/// App state: the tmux Windows in the sidebar, the one libghostty surface
/// running our tmux client, and a Browser per Window.
///
/// The terminal is a single `tmux attach` client attached straight to your
/// Sessions. Clicking a sidebar Window runs `switch-client -c <our tty> -t
/// <window>`, so tmux renders it with all its Panes, and anything you do
/// inside tmux (prefix+n, choose-tree, …) is reflected back into the sidebar.
@Observable
final class WorkspaceStore {
    private(set) var windows: [TmuxWindow] = []
    private(set) var serverRunning = true
    private(set) var selectedWindowID: String? {
        didSet { rememberSelection() }
    }
    private(set) var surface: TerminalSurfaceView?
    private(set) var terminalMessage: String?
    /// The Ghostty theme's colors; the header and sidebar follow them.
    private(set) var theme: TerminalTheme?

    var sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible") }
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
    @ObservationIgnored private let events = TmuxEvents()
    @ObservationIgnored private var browsers: [String: Browser] = [:]
    @ObservationIgnored private var persistWork: [String: DispatchWorkItem] = [:]
    /// Windows whose `@muxify_open` we consumed and are clearing.
    @ObservationIgnored private var consumingOpen = Set<String>()
    @ObservationIgnored private var rememberedWindowID: String?
    @ObservationIgnored private var clientTTY: String?
    /// A click we sent to tmux that the next snapshots may not reflect yet.
    @ObservationIgnored private var pendingSelection: (windowID: String, deadline: Date)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var isRefreshing = false
    /// Something changed while a snapshot was in flight; take another one.
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var started = false

    init() {
        // Browser state used to be kept here, keyed by window id; it now lives
        // on the tmux Windows (ADR 0003).
        UserDefaults.standard.removeObject(forKey: "browserURLs")
        UserDefaults.standard.removeObject(forKey: "browserVisible")
    }

    func start() {
        guard !started else { return }
        started = true
        GhosttyRuntime.shared.delegate = self
        theme = GhosttyRuntime.shared.theme
        guard GhosttyRuntime.shared.app != nil else {
            terminalMessage = "libghostty failed to initialize."
            return
        }
        guard Tmux.binary != nil else {
            terminalMessage = "tmux was not found. Install it with `brew install tmux`."
            return
        }
        installKeyMonitor()
        events.onEvent = { [weak self] in self?.handle($0) }
        refresh(attachIfNeeded: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Polling

    func refresh(attachIfNeeded: Bool = false) {
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = Tmux.snapshot()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.apply(snapshot, attachIfNeeded: attachIfNeeded)
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                }
            }
        }
    }

    /// tmux told us something changed. A Window switch in the Session we are
    /// showing moves the selection right away; the snapshot fills in the rest.
    private func handle(_ event: TmuxEvents.Event) {
        if case .sessionWindowChanged(let sessionID, let windowID) = event,
           pendingSelection == nil, selectedWindow?.sessionID == sessionID,
           windows.contains(where: { $0.id == windowID }) {
            selectedWindowID = windowID
        }
        refresh()
    }

    private func apply(_ snapshot: TmuxSnapshot, attachIfNeeded: Bool) {
        if windows != snapshot.windows { windows = snapshot.windows }
        if serverRunning != snapshot.serverRunning { serverRunning = snapshot.serverRunning }

        if attachIfNeeded, surface == nil {
            rememberedWindowID = snapshot.lastWindowID
            let last = snapshot.lastWindowID.flatMap { id in snapshot.windows.first { $0.id == id } }
            attach(to: (last ?? Self.initialWindow(in: snapshot.windows)).map(Target.init))
        } else {
            followClient(snapshot.clients)
        }
        consumeOpenRequests()

        // (Re)start listening once there is a Session to attach to.
        if snapshot.serverRunning, !events.isRunning,
           let sessionID = selectedWindow?.sessionID ?? windows.first?.sessionID {
            events.start(sessionID: sessionID)
        }

        if snapshot.serverRunning {
            let live = Set(windows.map(\.id))
            for (id, browser) in browsers where !live.contains(id) {
                browser.tearDown()
                browsers[id] = nil
            }
        }
    }

    /// The sidebar follows whatever window our tmux client is showing.
    private func followClient(_ clients: [TmuxClient]) {
        if clientTTY == nil { clientTTY = surface?.ttyName }
        if let tty = clientTTY, let client = clients.first(where: { $0.tty == tty }) {
            if let pending = pendingSelection, client.windowID == pending.windowID || Date() > pending.deadline {
                pendingSelection = nil
            }
            if pendingSelection == nil, selectedWindowID != client.windowID {
                selectedWindowID = client.windowID
            }
        } else if surface == nil, let selectedWindowID, !windows.contains(where: { $0.id == selectedWindowID }) {
            self.selectedWindowID = nil
        }
    }

    /// The current window of the most recently used Session.
    private static func initialWindow(in windows: [TmuxWindow]) -> TmuxWindow? {
        windows.filter(\.isActive).max { $0.sessionActivity < $1.sessionActivity } ?? windows.first
    }

    /// Stored server-wide in tmux rather than in preferences, so it can't
    /// outlive the server and point at a reused window id.
    private func rememberSelection() {
        guard let selectedWindowID, selectedWindowID != rememberedWindowID else { return }
        rememberedWindowID = selectedWindowID
        Tmux.runAsync(["set-option", "-gq", Tmux.lastWindowOption, selectedWindowID])
    }

    // MARK: - Terminal

    private struct Target {
        let sessionID: String
        let windowID: String
        let path: String?

        init(_ window: TmuxWindow) {
            self.init(sessionID: window.sessionID, windowID: window.id, path: window.path)
        }

        init(sessionID: String, windowID: String, path: String?) {
            self.sessionID = sessionID
            self.windowID = windowID
            self.path = path
        }

        var tmuxTarget: String { "\(sessionID):\(windowID)" }
    }

    /// Starts our tmux client on `target`, or a fresh session if there is none.
    private func attach(to target: Target?) {
        let args = target.map { ["-u", "attach-session", "-t", $0.tmuxTarget] }
            ?? ["-u", "new-session", "-A", "-s", "main", "-c", NSHomeDirectory()]
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
        attach(to: (selectedWindow ?? Self.initialWindow(in: windows)).map(Target.init))
    }

    func select(_ window: TmuxWindow) {
        switchClient(to: Target(window))
    }

    /// ⌘1–9: the Window with that tmux index in the current Session.
    func selectWindow(index: Int) {
        guard let current = selectedWindow else { return }
        let siblings = windows.filter { $0.sessionID == current.sessionID }
        if let window = siblings.first(where: { $0.index == index }) { select(window) }
    }

    private func switchClient(to target: Target) {
        selectedWindowID = target.windowID
        pendingSelection = (target.windowID, Date().addingTimeInterval(2))
        focusTerminal()
        guard let surface, !surface.processExited, let tty = clientTTY ?? surface.ttyName else {
            attach(to: target)
            return
        }
        clientTTY = tty
        Tmux.runAsync(["switch-client", "-c", tty, "-t", target.tmuxTarget]) { [weak self] _ in self?.refresh() }
    }

    var isTerminalFocused: Bool {
        guard let surface else { return false }
        return surface.window?.firstResponder === surface
    }

    /// Keyboard focus is in the current Window's Browser (its page or omnibox).
    var isBrowserFocused: Bool {
        !isTerminalFocused && currentBrowser?.isOpen == true
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
        // -d, then switch only our client: other Sessions' current windows stay put.
        let args = ["new-window", "-d", "-P", "-F", "#{window_id}", "-t", "\(sessionID):", "-c", sibling.path]
        Tmux.runAsync(args) { [weak self] result in
            guard let self, case .success(let output) = result else { return }
            let windowID = output.trimmingCharacters(in: .whitespacesAndNewlines)
            self.switchClient(to: Target(sessionID: sessionID, windowID: windowID, path: sibling.path))
        }
    }

    func newSession() {
        let cwd = selectedWindow?.path ?? NSHomeDirectory()
        var args = ["new-session", "-d", "-P", "-F", "#{session_id}:#{window_id}", "-c", cwd]
        let name = (cwd as NSString).lastPathComponent.replacingOccurrences(of: ".", with: "_")
        if !name.isEmpty, !windows.contains(where: { $0.sessionName == name }) { args += ["-s", name] }
        Tmux.runAsync(args) { [weak self] result in
            guard let self, case .success(let output) = result else { return }
            let ids = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").map(String.init)
            guard ids.count == 2 else { return }
            self.switchClient(to: Target(sessionID: ids[0], windowID: ids[1], path: cwd))
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

    /// The Window's Browser, restored from its tmux options on first use.
    func browser(for windowID: String) -> Browser {
        if let browser = browsers[windowID] { return browser }
        let stored = windows.first { $0.id == windowID }?.storedBrowser ?? StoredBrowser()
        let browser = Browser(windowID: windowID, stored: stored)
        browser.onChange = { [weak self] in self?.persist($0) }
        browsers[windowID] = browser
        return browser
    }

    var currentBrowser: Browser? {
        selectedWindowID.map(browser(for:))
    }

    /// For the sidebar badge, without restoring Browsers nobody has looked at.
    func tabCount(for window: TmuxWindow) -> Int {
        browsers[window.id]?.tabs.count ?? window.storedBrowser.tabURLs.count
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    func setBrowserOpen(_ open: Bool) {
        currentBrowser?.setOpen(open)
        if !open { focusTerminal() }
    }

    func toggleBrowser() {
        guard let browser = currentBrowser else { return }
        setBrowserOpen(!browser.isOpen)
    }

    func focusAddressBar() {
        guard let browser = currentBrowser else { return }
        browser.setOpen(true)
        browser.wantsAddressFocus = true
    }

    /// Menu actions for the Browser. Their shortcuts only count when focus is
    /// outside the terminal, where Ghostty/tmux bindings own the keyboard;
    /// clicking the menu item always works.
    func browserCommand(_ body: (Browser) -> Void) {
        if NSApp.currentEvent?.type == .keyDown, isTerminalFocused { return }
        guard let browser = currentBrowser else { return }
        body(browser)
        if !browser.isOpen { focusTerminal() }
    }

    /// Opens `url` as a Tab in a Window's Browser (the current Window by
    /// default). For another Window it happens quietly: you aren't moved.
    func openInBrowser(_ url: URL, windowID: String? = nil) {
        guard let id = windowID ?? selectedWindowID else {
            NSWorkspace.shared.open(url)
            return
        }
        browser(for: id).open(url)
    }

    /// Programs inside a Window open Tabs with `tmux set -w @muxify_open <url>`
    /// (several URLs may be space-separated); we open them and clear the option.
    private func consumeOpenRequests() {
        for window in windows where !window.openRequests.isEmpty && !consumingOpen.contains(window.id) {
            consumingOpen.insert(window.id)
            for request in window.openRequests {
                if let url = Omnibox.url(for: request) { openInBrowser(url, windowID: window.id) }
            }
            Tmux.runAsync(["set-option", "-wqu", "-t", window.id, Tmux.openOption]) { [weak self] _ in
                self?.consumingOpen.remove(window.id)
            }
        }
    }

    /// Writes a Browser back onto its tmux Window, coalescing bursts of
    /// changes (redirects, quick Tab switching) into one tmux call.
    private func persist(_ browser: Browser) {
        let id = browser.windowID
        persistWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak browser] in
            self?.persistWork[id] = nil
            guard let browser else { return }
            Tmux.runAsync(browser.stored.setOptionArgs(windowID: id))
        }
        persistWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Keyboard

    /// Shortcuts the menu can't express. ⌘W closes a Tab when the Browser has
    /// focus and never the app window (which would quit Muxify); ⌃Tab and
    /// ⌃⇧Tab switch Tabs; ⌃⌘S, the macOS sidebar standard, also toggles the
    /// sidebar. Terminal focus is left to Ghostty/tmux bindings.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.terminalHost.window else { return event }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let key = event.charactersIgnoringModifiers?.lowercased()

            if flags == [.control, .command], key == "s" {
                self.toggleSidebar()
                return nil
            }
            if flags == .command, key == "w" {
                if self.isBrowserFocused { self.browserCommand { $0.closeActiveTab() } }
                return nil
            }
            if event.keyCode == 0x30, flags == .control || flags == [.control, .shift], self.isBrowserFocused {
                self.currentBrowser?.selectTab(offset: flags.contains(.shift) ? -1 : 1)
                return nil
            }
            return event
        }
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
            openInBrowser(target, windowID: value("window"))
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
        // Cmd+click on a link in the terminal opens it as a Tab in this Window's Browser.
        if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            openInBrowser(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func ghosttyThemeChanged(_ theme: TerminalTheme) {
        self.theme = theme
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
