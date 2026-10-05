import AppKit
import SwiftUI

struct SidebarView: View {
    let store: WorkspaceStore

    /// Expanded sessions, by name (names survive tmux server restarts, ids don't).
    @State private var expanded: Set<String> = Self.loadExpanded()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(store.sessions) { session in
                            let isExpanded = expanded.contains(session.name)
                            SessionHeader(
                                session: session,
                                isExpanded: isExpanded,
                                containsSelection: session.windows.contains { $0.id == store.selectedWindowID },
                                onToggle: { toggle(session.name) },
                                onNewWindow: { store.newWindow(inSession: session.id) }
                            )
                            if isExpanded {
                                ForEach(session.windows) { window in
                                    WindowRow(
                                        window: window,
                                        isSelected: window.id == store.selectedWindowID,
                                        tabCount: store.tabCount(for: window)
                                    )
                                        .id(window.id)
                                        .onTapGesture { store.select(window) }
                                        .contextMenu { menu(for: window) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                .onChange(of: store.selectedWindowID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
            Divider()
            footer
        }
        .overlay {
            if store.windows.isEmpty {
                Text(store.serverRunning ? "No windows" : "No tmux server")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        // Moving to another session (click, tmux navigation, new window) opens it.
        .onChange(of: store.selectedWindow?.sessionName, initial: true) { _, name in
            guard let name, !expanded.contains(name) else { return }
            withAnimation(.easeOut(duration: 0.15)) { expanded.insert(name) }
        }
        .onChange(of: expanded) { _, value in
            UserDefaults.standard.set(Array(value), forKey: Self.expandedKey)
        }
    }

    private static let expandedKey = "expandedSessions"

    private static func loadExpanded() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: expandedKey) ?? [])
    }

    private func toggle(_ name: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                store.newWindow()
            } label: {
                Label("New Window", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("New tmux window in this session (⌘T)")
            Spacer()
            Button {
                store.newSession()
            } label: {
                Image(systemName: "rectangle.stack.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New tmux session (⌘N)")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func menu(for window: TmuxWindow) -> some View {
        Button("Rename Window…") { rename(window) }
        Button("New Window in \(window.sessionName)") { store.newWindow(inSession: window.sessionID) }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(window.path, forType: .string)
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: window.path)
        }
        Divider()
        Button("Kill Window…", role: .destructive) { confirmKill(window) }
    }

    private func rename(_ window: TmuxWindow) {
        let alert = NSAlert()
        alert.messageText = "Rename tmux window"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = window.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
            store.renameWindow(window, to: field.stringValue)
        }
    }

    private func confirmKill(_ window: TmuxWindow) {
        let alert = NSAlert()
        alert.messageText = "Kill \"\(window.displayTitle)\"?"
        alert.informativeText = "This closes tmux window \(window.sessionName):\(window.index) and every process in its \(window.paneCount) pane(s)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill Window")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.killWindow(window)
        }
    }
}

private struct SessionHeader: View {
    let session: SessionGroup
    let isExpanded: Bool
    let containsSelection: Bool
    let onToggle: () -> Void
    let onNewWindow: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
            Text(session.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovering {
                Button(action: onNewWindow) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("New window in \(session.name)")
            } else {
                if !isExpanded, session.windows.contains(where: { $0.hasBell || $0.hasActivity }) {
                    Circle()
                        .fill(session.windows.contains(where: \.hasBell) ? Color.orange : Color.accentColor)
                        .frame(width: 5, height: 5)
                }
                Text("\(session.windows.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { hovering = $0 }
        .padding(.top, 2)
    }

    /// A collapsed session hiding the current window still shows where you are.
    private var highlighted: Bool { containsSelection && !isExpanded }

    private var background: Color {
        if highlighted { return Color.accentColor.opacity(0.12) }
        return hovering ? Color.primary.opacity(0.06) : .clear
    }
}

private struct WindowRow: View {
    let window: TmuxWindow
    let isSelected: Bool
    let tabCount: Int

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(window.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if window.hasBell || window.hasActivity {
                    Circle()
                        .fill(isSelected ? Color.white : (window.hasBell ? Color.orange : Color.accentColor))
                        .frame(width: 5, height: 5)
                }
                if tabCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "globe")
                        Text("\(tabCount)")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryStyle)
                    .help("\(tabCount) browser tab(s)")
                }
                if window.paneCount > 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "rectangle.split.2x1")
                        Text("\(window.paneCount)")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryStyle)
                }
            }
            if let branch = window.branch {
                Text(branch)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(secondaryStyle)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.leading, 24)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering = $0 }
        .help("\(window.sessionName):\(window.index) — \(window.abbreviatedPath)")
    }

    private var secondaryStyle: Color {
        isSelected ? Color.white.opacity(0.85) : Color.secondary
    }

    private var background: Color {
        if isSelected { return .accentColor }
        return hovering ? Color.primary.opacity(0.07) : .clear
    }
}
