import AppKit
import MuxifyCore

extension PaletteItem {
    var readTarget: WorkspaceStore.MarkReadTarget? {
        switch ref {
        case .topic(let id, _): return .topic(id)
        case .session(let session): return .session(session.id)
        case .window(let window): return .window(window.id)
        case .agent(let agent): return .pane(agent.paneID)
        case .project, .choice, .command: return nil
        }
    }
}

extension CommandPalette {
    func performRowAction(_ action: PaletteAction, item: PaletteItem) {
        guard let store else { return }
        if action == .markRead {
            close()
            store.markRead(item.readTarget)
            return
        }
        if case .topic(let id, _) = item.ref,
           let topic = store.topicWatcher.records.first(where: { $0.id == id }) {
            switch action {
            case .snoozeTopic: begin(.snooze(topic), keepingHistory: true)
            case .startZen:
                if store.topicWatcher.zen == nil { begin(.zen(id), keepingHistory: true) }
                else { close(); store.endZen() }
            case .settleTopic: begin(.confirm(PaletteConfirmation(.settle(topic))), keepingHistory: true)
            case .forgetTopic: begin(.confirm(PaletteConfirmation(.forget(topic))), keepingHistory: true)
            case .rename: begin(.text(.renameTopic(topic)), text: topic.title ?? "", keepingHistory: true)
            case .addProjectToTopic: store.refreshProjects(); begin(.addProject(topic), keepingHistory: true)
            case .suggestTopicTitle:
                close()
                store.suggestTopicTitle(for: id) { store.renameTopic(id, to: $0) }
            case .pinTopic: close(); store.pinTopic(id, true)
            case .unpinTopic: close(); store.pinTopic(id, false)
            case .unsnoozeTopic: close(); store.unsnoozeTopic(id)
            case .reopenTopic: close(); store.reopenTopic(id, .reopen)
            case .startTopicFresh: close(); store.reopenTopic(id, .startFresh)
            default: break
            }
            return
        }
        let window: TmuxWindow?
        let scope: MoveDraft.Scope
        let paneID: String?
        switch item.ref {
        case .window(let value): window = value; scope = .window; paneID = nil
        case .session(let session): window = session.windows.first; scope = .session; paneID = nil
        case .agent(let agent): window = store.windows.first { $0.id == agent.windowID }; scope = .pane; paneID = agent.paneID
        default: window = nil; scope = .window; paneID = nil
        }
        switch action {
        case .revealFolder: close(); NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.path)
        case .move:
            if let window { begin(.move(MoveDraft(window: window, paneID: paneID ?? window.activePaneID, scope: scope)), keepingHistory: true) }
        case .rename:
            guard let window else { break }
            if scope == .session { begin(.text(.renameSession(window)), text: window.sessionName, keepingHistory: true) }
            else { begin(.text(.renameWindow(window)), text: window.name, keepingHistory: true) }
        case .killWindow:
            if let window { begin(.confirm(PaletteConfirmation(.killWindow(window))), keepingHistory: true) }
        case .killSession:
            if let window { begin(.confirm(PaletteConfirmation(.killSession(window))), keepingHistory: true) }
        case .lockSession, .unlockSession:
            if let window { close(); store.setLock(ofSession: window.sessionID, action == .lockSession) }
        case .newWindow:
            if let window { close(); store.newWindow(beside: window) }
        case .removeFromTopic:
            if let window {
                close()
                if scope == .session { store.removeFromTopic(window) }
                else { store.removeWindowFromTopic(window) }
            }
        default: break
        }
    }
}
