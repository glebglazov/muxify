import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var sidebarHidden: Bool { columnVisibility == .detailOnly }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store, toggleSidebar: toggleSidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                // With the sidebar collapsed its controls would be gone, so a
                // slim bar next to the traffic lights brings them back.
                if sidebarHidden {
                    HStack(spacing: 2) {
                        TitlebarButton(systemName: "sidebar.left", help: "Show Sidebar (⌃⌘S)", action: toggleSidebar)
                        Spacer()
                        BrowserToggle(store: store)
                    }
                    .padding(.leading, TitlebarMetrics.trafficLightsWidth)
                    .padding(.trailing, 8)
                    .frame(height: TitlebarMetrics.height)
                    .background(WindowDragArea())
                }
                TerminalArea(store: store)
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            // Names the window for the Window menu and Mission Control.
            .navigationTitle(store.selectedWindow?.sessionName ?? "Muxify")
            .inspector(isPresented: $store.browserVisible) {
                browser
                    .ignoresSafeArea(.container, edges: .top)
                    .inspectorColumnWidth(min: 320, ideal: 640, max: 1800)
            }
        }
        .onAppear { store.start() }
        .onOpenURL { store.handle($0) }
    }

    private func toggleSidebar() {
        withAnimation(.easeOut(duration: 0.2)) {
            columnVisibility = sidebarHidden ? .all : .detailOnly
        }
    }

    @ViewBuilder
    private var browser: some View {
        if let tab = store.currentBrowserTab {
            BrowserPanel(tab: tab) { store.toggleBrowser() }
                .id(tab.windowID)
        } else {
            Text("Select a tmux window")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TerminalArea: View {
    let store: WorkspaceStore

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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TerminalHostRepresentable: NSViewRepresentable {
    let host: TerminalHostView

    func makeNSView(context: Context) -> TerminalHostView { host }
    func updateNSView(_ nsView: TerminalHostView, context: Context) {}
}

// MARK: - Title bar controls

enum TitlebarMetrics {
    /// Height of the strip that lines up with the traffic lights.
    static let height: CGFloat = 36
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
    }
}

struct BrowserToggle: View {
    let store: WorkspaceStore

    var body: some View {
        TitlebarButton(
            systemName: "sidebar.right",
            help: store.browserVisible ? "Hide Browser (⇧⌘B)" : "Show Browser (⇧⌘B)",
            isOn: store.browserVisible,
            action: store.toggleBrowser
        )
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
