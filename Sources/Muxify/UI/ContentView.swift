import SwiftUI

struct ContentView: View {
    let store: WorkspaceStore
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 260
    /// One width for every Window's Browser.
    @AppStorage("browserWidth") private var browserWidth: Double = 640

    var body: some View {
        GeometryReader { proxy in
            let sidebar = store.sidebarVisible ? clamp(sidebarWidth, 180, 420) : 0
            let browserMax = max(320, proxy.size.width - sidebar - 360)
            // Panels appear and disappear without animation, so switching
            // between Windows with and without a Browser is instant.
            HStack(spacing: 0) {
                if store.sidebarVisible {
                    SidebarView(store: store)
                        .frame(width: sidebar)
                        .chrome(theme: store.theme, material: .sidebar)
                    PanelResizeHandle(width: $sidebarWidth, range: 180...420, edge: .leading)
                }
                TerminalArea(store: store)
                if let browser = store.currentBrowser, browser.isOpen {
                    PanelResizeHandle(width: $browserWidth, range: 320...browserMax, edge: .trailing)
                    BrowserPanel(browser: browser)
                        .id(browser.windowID)
                        .frame(width: clamp(browserWidth, 320, browserMax))
                }
            }
        }
        .padding(.top, TitlebarMetrics.height)
        // An overlay, so it is above everything for clicks: scroll views below
        // (sidebar list, tab strip) reach up under the title bar area and would
        // otherwise swallow clicks on the toggles.
        .overlay(alignment: .top) { HeaderBar(store: store) }
        .ignoresSafeArea()
        // Names the window for the Window menu and Mission Control.
        .navigationTitle(store.selectedWindow?.sessionName ?? "Muxify")
        .onAppear { store.start() }
        .onOpenURL { store.handle($0) }
    }

    private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}

/// The fixed strip along the top: room for the traffic lights, the window's
/// drag handle, and the two panel toggles on the right.
private struct HeaderBar: View {
    let store: WorkspaceStore

    var body: some View {
        let browserOpen = store.currentBrowser?.isOpen ?? false
        HStack(spacing: 2) {
            Spacer()
            TitlebarButton(
                systemName: "sidebar.left",
                help: store.sidebarVisible ? "Hide Sidebar (⌘S)" : "Show Sidebar (⌘S)",
                isOn: store.sidebarVisible,
                action: store.toggleSidebar
            )
            TitlebarButton(
                systemName: "sidebar.right",
                help: browserOpen ? "Hide Browser (⌘B)" : "Show Browser (⌘B)",
                isOn: browserOpen,
                action: store.toggleBrowser
            )
        }
        .padding(.leading, TitlebarMetrics.trafficLightsWidth)
        .padding(.trailing, 8)
        .frame(height: TitlebarMetrics.height)
        .background(WindowDragArea())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: store.theme?.separator ?? .separatorColor))
                .frame(height: 1)
        }
        .chrome(theme: store.theme, material: .titlebar)
    }
}

private extension View {
    /// Header and sidebar take their background from the Ghostty theme, and
    /// their text follows its lightness, so a dark theme stays readable while
    /// macOS is in light mode. Without a theme they use the system materials.
    @ViewBuilder
    func chrome(theme: TerminalTheme?, material: NSVisualEffectView.Material) -> some View {
        if let theme {
            background(Color(nsColor: theme.chrome))
                .environment(\.colorScheme, theme.isDark ? .dark : .light)
        } else {
            background(VisualEffectBackground(material: material))
        }
    }
}

private struct TerminalArea: View {
    let store: WorkspaceStore
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        ZStack {
            TerminalHostRepresentable(host: store.terminalHost)
            if store.surface == nil { placeholder }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            if let message = store.terminalMessage {
                Text(message).foregroundStyle(.secondary)
            } else if store.windows.isEmpty {
                Text(store.serverRunning ? "No tmux windows" : "tmux server is not running")
                    .foregroundStyle(.secondary)
                Button("New tmux Session") { store.newSession() }
            } else {
                Text("Detached from tmux").foregroundStyle(.secondary)
                Button("Reattach") { store.reattach() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: store.theme?.background ?? .windowBackgroundColor))
        .environment(\.colorScheme, store.theme.map { $0.isDark ? .dark : .light } ?? systemColorScheme)
    }
}

private struct TerminalHostRepresentable: NSViewRepresentable {
    let host: TerminalHostView

    func makeNSView(context: Context) -> TerminalHostView { host }
    func updateNSView(_ nsView: TerminalHostView, context: Context) {}
}

// MARK: - Title bar controls

enum TitlebarMetrics {
    /// Height of the header; the traffic lights sit centred in it.
    static let height: CGFloat = 30
    /// Room to leave on the leading edge for the traffic lights.
    static let trafficLightsWidth: CGFloat = 78
}

struct TitlebarButton: View {
    let systemName: String
    let help: String
    var isOn = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .actsOnFirstClick()
    }
}

private extension View {
    /// Like toolbar buttons: a click on an inactive window both activates it
    /// and presses the button.
    @ViewBuilder
    func actsOnFirstClick() -> some View {
        if #available(macOS 15.0, *) {
            allowsWindowActivationEvents(true)
        } else {
            self
        }
    }
}

/// Empty space that moves the window when dragged, since there is no title
/// bar to grab anymore.
struct WindowDragArea: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        } else {
            Color.clear
        }
    }
}

/// The divider between terminal and Browser; drag it to resize the Browser.
private struct PanelResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// Which side of the handle the resized panel is on.
    let edge: HorizontalEdge

    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? width
                                if startWidth == nil { startWidth = start }
                                let delta = edge == .leading ? value.translation.width : -value.translation.width
                                width = min(max(start + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            }
            .zIndex(1)
    }
}

/// Native translucent material (the sidebar and title bar look).
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
