import AppKit
import GhosttyKit

/// Things libghostty asks the host app to do that only the app can decide.
protocol GhosttyRuntimeDelegate: AnyObject {
    func ghosttyOpenURL(_ url: URL)
    func ghosttyNewTab()
    func ghosttyNewWindow()
    func ghosttyNewSplit(_ direction: ghostty_action_split_direction_e)
    func ghosttyGotoSplit(_ direction: ghostty_action_goto_split_e)
    func ghosttyToggleSplitZoom()
    func ghosttyEqualizeSplits()
    func ghosttyGotoTab(_ tab: Int32)
    func ghosttySurfaceClosed(_ view: TerminalSurfaceView)
}

/// Owns the single `ghostty_app_t` and bridges libghostty's C callbacks.
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    weak var delegate: GhosttyRuntimeDelegate?

    private init() {}

    /// Must run before any surface is created.
    func start() {
        guard app == nil else { return }
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            NSLog("muxify: ghostty_init failed")
            return
        }
        config = Self.loadConfig()

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { _ in
                DispatchQueue.main.async { GhosttyRuntime.shared.tick() }
            },
            action_cb: { _, target, action in
                GhosttyRuntime.shared.handle(action: action, target: target)
            },
            read_clipboard_cb: { userdata, location, state in
                GhosttyRuntime.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, string, state, request in
                GhosttyRuntime.confirmReadClipboard(userdata, string: string, state: state, request: request)
            },
            write_clipboard_cb: { _, location, content, count, _ in
                GhosttyRuntime.writeClipboard(location: location, content: content, count: count)
            },
            close_surface_cb: { userdata, _ in
                guard let view = TerminalSurfaceView.from(userdata) else { return }
                DispatchQueue.main.async { GhosttyRuntime.shared.delegate?.ghosttySurfaceClosed(view) }
            }
        )
        app = ghostty_app_new(&runtime, config)
        if app == nil { NSLog("muxify: ghostty_app_new failed") }

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            if let app = GhosttyRuntime.shared.app { ghostty_app_set_focus(app, true) }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            if let app = GhosttyRuntime.shared.app { ghostty_app_set_focus(app, false) }
        }
        center.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
        ) { _ in
            if let app = GhosttyRuntime.shared.app { ghostty_app_keyboard_changed(app) }
        }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func setColorScheme(dark: Bool) {
        guard let app else { return }
        ghostty_app_set_color_scheme(app, dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
    }

    func reloadConfig() {
        guard let app, let fresh = Self.loadConfig() else { return }
        ghostty_app_update_config(app, fresh)
        if let old = config { ghostty_config_free(old) }
        config = fresh
    }

    /// The user's normal Ghostty config (~/.config/ghostty/config etc.), so
    /// fonts, themes and keybinds match their standalone Ghostty.
    private static func loadConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        for i in 0..<ghostty_config_diagnostics_count(config) {
            let diagnostic = ghostty_config_get_diagnostic(config, i)
            if let message = diagnostic.message { NSLog("muxify: ghostty config: \(String(cString: message))") }
        }
        return config
    }

    // MARK: - Actions

    private func handle(action: ghostty_action_s, target: ghostty_target_s) -> Bool {
        let surfaceView: TerminalSurfaceView? = target.tag == GHOSTTY_TARGET_SURFACE
            ? TerminalSurfaceView.from(ghostty_surface_userdata(target.target.surface))
            : nil

        switch action.tag {
        case GHOSTTY_ACTION_QUIT:
            NSApp.terminate(nil)
        case GHOSTTY_ACTION_OPEN_URL:
            let raw = action.action.open_url
            guard let ptr = raw.url else { return false }
            let data = Data(bytes: ptr, count: Int(raw.len))
            let string = String(decoding: data, as: UTF8.self)
            guard let url = URL(string: string) ?? URL(string: string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else {
                return false
            }
            delegate?.ghosttyOpenURL(url)
        case GHOSTTY_ACTION_MOUSE_SHAPE:
            surfaceView?.setCursorShape(action.action.mouse_shape)
        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            NSCursor.setHiddenUntilMouseMoves(action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN)
        case GHOSTTY_ACTION_NEW_TAB:
            delegate?.ghosttyNewTab()
        case GHOSTTY_ACTION_NEW_WINDOW:
            delegate?.ghosttyNewWindow()
        case GHOSTTY_ACTION_NEW_SPLIT:
            delegate?.ghosttyNewSplit(action.action.new_split)
        case GHOSTTY_ACTION_GOTO_SPLIT:
            delegate?.ghosttyGotoSplit(action.action.goto_split)
        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            delegate?.ghosttyToggleSplitZoom()
        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            delegate?.ghosttyEqualizeSplits()
        case GHOSTTY_ACTION_GOTO_TAB:
            delegate?.ghosttyGotoTab(action.action.goto_tab.rawValue)
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            // tmux client exited (detach, server gone): skip libghostty's
            // "press any key" screen and let the app show its own placeholder.
            // Deferred because freeing a surface inside its own callback is unsafe.
            guard let surfaceView else { return false }
            DispatchQueue.main.async { self.delegate?.ghosttySurfaceClosed(surfaceView) }
        case GHOSTTY_ACTION_RELOAD_CONFIG:
            reloadConfig()
        case GHOSTTY_ACTION_RING_BELL:
            // tmux rings the bell for activity in other Windows (monitor-activity),
            // which is constant with agents running, so never beep. Like
            // Ghostty's default, only ask for attention while in the background.
            if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        case GHOSTTY_ACTION_SET_TITLE, GHOSTTY_ACTION_PWD, GHOSTTY_ACTION_CELL_SIZE,
             GHOSTTY_ACTION_COLOR_CHANGE, GHOSTTY_ACTION_CONFIG_CHANGE, GHOSTTY_ACTION_MOUSE_OVER_LINK,
             GHOSTTY_ACTION_RENDERER_HEALTH, GHOSTTY_ACTION_SCROLLBAR:
            // Sidebar labels come from tmux; nothing to do for these in the POC.
            return true
        default:
            return false
        }
        return true
    }

    // MARK: - Clipboard

    private static func readClipboard(_ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) -> Bool {
        guard let surface = TerminalSurfaceView.from(userdata)?.surface else { return false }
        let string = NSPasteboard.general.string(forType: .string) ?? ""
        string.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, false) }
        return true
    }

    private static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let surface = TerminalSurfaceView.from(userdata)?.surface else { return }
        // Pastes the user initiated are confirmed; programs reading the
        // clipboard through OSC 52 get nothing.
        let allowed = request == GHOSTTY_CLIPBOARD_REQUEST_PASTE
        let value = allowed ? (string.map { String(cString: $0) } ?? "") : ""
        value.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, true) }
    }

    private static func writeClipboard(location: ghostty_clipboard_e, content: UnsafePointer<ghostty_clipboard_content_s>?, count: Int) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD, let content, count > 0 else { return }
        var text: String?
        for i in 0..<count {
            let item = content[i]
            guard let data = item.data else { continue }
            let mime = item.mime.map { String(cString: $0) } ?? "text/plain"
            if mime.hasPrefix("text/plain") || text == nil {
                text = String(cString: data)
            }
        }
        guard let text else { return }
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
