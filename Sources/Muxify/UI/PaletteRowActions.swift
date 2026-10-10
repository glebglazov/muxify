import AppKit
import MuxifyCore

extension CommandPalette {
    func performRowAction(_ action: PaletteAction, item: PaletteItem) {
        guard let store else { return }
        if case .topic(let id, _) = item.ref,
           let topic = store.topicWatcher.records.first(where: { $0.id == id }) {
            switch action {
            case .snooze: begin(.snooze(topic), keepingHistory: true)
            case .zen:
                if store.topicWatcher.zen == nil { begin(.zen(id), keepingHistory: true) }
                else { close(); store.endZen() }
            case .settle: begin(.confirm(PaletteConfirmation(.settle(topic))), keepingHistory: true)
            case .forget: begin(.confirm(PaletteConfirmation(.forget(topic))), keepingHistory: true)
            case .rename: begin(.text(.renameTopic(topic)), text: topic.title ?? "", keepingHistory: true)
            case .addProject: store.refreshProjects(); begin(.addProject(topic), keepingHistory: true)
            case .suggest:
                close()
                store.suggestTopicTitle(for: id) { store.renameTopic(id, to: $0) }
            case .pin: close(); store.pinTopic(id, true)
            case .unpin: close(); store.pinTopic(id, false)
            case .unsnooze: close(); store.unsnoozeTopic(id)
            case .reopen: close(); store.reopenTopic(id, .reopen)
            case .startFresh: close(); store.reopenTopic(id, .startFresh)
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
        case .reveal: close(); NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.path)
        case .move:
            if let window { begin(.move(MoveDraft(window: window, paneID: paneID ?? window.activePaneID, scope: scope)), keepingHistory: true) }
        case .rename:
            if let window { begin(.text(.renameWindow(window)), text: window.name, keepingHistory: true) }
        case .killWindow:
            if let window { begin(.confirm(PaletteConfirmation(.killWindow(window))), keepingHistory: true) }
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
