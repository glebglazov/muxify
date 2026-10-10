import AppKit
import SwiftUI
import MuxifyCore

struct TopicMembershipMenu: View {
    let store: WorkspaceStore
    let source: TopicMembershipPlan.Source

    private var currentSource: TopicMembershipPlan.Source {
        (try? source.resolved(in: store.windows)) ?? source
    }

    private var isSession: Bool {
        if case .session = source { return true }
        return false
    }

    fileprivate var moveTitle: String { isSession ? "Move to Topic" : "Move Window to Topic" }

    var body: some View {
        Group {
            Button(moveTitle + "…") { openMove() }
            Button(isSession ? "New Topic from this Session" : "New Topic from this Window") { openMove() }
            if !isSession {
                Button("New Topic from this Pane") { store.palette.openMove(currentSource.window, scope: .pane) }
            }
            if isSession, currentSource.window.topicID != nil {
                Button("Remove from Topic") { store.removeFromTopic(currentSource.window) }
            }
        }
        .disabled(store.changingTopic)
    }

    fileprivate func openMove() {
        store.palette.openMove(currentSource.window, scope: isSession ? .session : .window)
    }

}

extension View {
    func topicMembershipActions(store: WorkspaceStore, source: TopicMembershipPlan.Source) -> some View {
        let menu = TopicMembershipMenu(store: store, source: source)
        return accessibilityActions {
            Button(menu.moveTitle + "…") { menu.openMove() }
        }
    }
}
