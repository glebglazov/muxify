import SwiftUI
import WebKit

/// The right-hand browser sidebar: navigation controls, an omnibox and the page.
struct BrowserPanel: View {
    let tab: BrowserTab
    let onClose: () -> Void

    @State private var address = ""
    @State private var ports: [Int] = []
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                WebViewHost(tab: tab)
                if !tab.hasPage { emptyState }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            address = tab.urlString
            scanPorts()
            consumeFocusRequest()
        }
        .onChange(of: tab.urlString) { _, newValue in
            if !addressFocused { address = newValue }
        }
        .onChange(of: tab.wantsAddressFocus) { _, _ in consumeFocusRequest() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            ToolbarIconButton(systemName: "chevron.left", help: "Back", action: tab.goBack)
                .disabled(!tab.canGoBack)
            ToolbarIconButton(systemName: "chevron.right", help: "Forward", action: tab.goForward)
                .disabled(!tab.canGoForward)
            ToolbarIconButton(
                systemName: tab.isLoading ? "xmark" : "arrow.clockwise",
                help: tab.isLoading ? "Stop" : "Reload",
                action: tab.reloadOrStop
            )
            .disabled(!tab.hasPage)

            addressField
                .padding(.horizontal, 4)

            Menu {
                Button("Open in Default Browser", action: tab.openInDefaultBrowser).disabled(!tab.hasPage)
                Button("Copy URL", action: tab.copyURL).disabled(!tab.hasPage)
                Divider()
                Button("Close Browser", action: onClose)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .overlay(alignment: .bottom) { progressBar }
    }

    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: addressIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search or enter URL", text: $address)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($addressFocused)
                .onSubmit(submit)
                .onExitCommand {
                    address = tab.urlString
                    focusPage()
                }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    addressFocused ? Color.accentColor : Color.primary.opacity(0.14),
                    lineWidth: addressFocused ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { addressFocused = true }
    }

    private var addressIcon: String {
        if addressFocused || !tab.hasPage { return "magnifyingglass" }
        return tab.urlString.hasPrefix("https://") ? "lock.fill" : "globe"
    }

    @ViewBuilder
    private var progressBar: some View {
        if tab.isLoading {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: max(8, proxy.size.width * tab.progress), height: 2)
                    .animation(.easeOut(duration: 0.2), value: tab.progress)
            }
            .frame(height: 2)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Search or enter a URL")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if !ports.isEmpty {
                VStack(spacing: 8) {
                    Text("Listening in this tmux window")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 8) {
                        ForEach(ports.prefix(6), id: \.self) { port in
                            // Concatenate, so the port isn't locale-formatted ("61.890").
                            Button("localhost:" + String(port)) {
                                tab.open("http://localhost:\(port)")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions

    private func submit() {
        tab.open(address)
        focusPage()
    }

    /// Only explicit requests (opening the panel, ⌘L) take focus; merely
    /// switching tmux windows keeps the keyboard in the terminal.
    private func consumeFocusRequest() {
        guard tab.wantsAddressFocus else { return }
        tab.wantsAddressFocus = false
        DispatchQueue.main.async { addressFocused = true }
    }

    private func focusPage() {
        addressFocused = false
        DispatchQueue.main.async { tab.webView.window?.makeFirstResponder(tab.webView) }
    }

    private func scanPorts() {
        DevServerScanner.scan(windowID: tab.windowID) { ports = $0 }
    }
}

private struct ToolbarIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering && isEnabled ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .secondary : .quaternary)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Hosts a tab's long-lived WKWebView. The web view is re-parented rather
/// than recreated, so pages survive switching tmux windows.
private struct WebViewHost: NSViewRepresentable {
    let tab: BrowserTab

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container)
    }

    private func attach(to container: NSView) {
        let webView = tab.webView
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
