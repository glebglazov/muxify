import SwiftUI

struct ClientVerification: ViewModifier {
    let store: WorkspaceStore

    func body(content: Content) -> some View {
        #if DEBUG
        content.overlay(alignment: .bottomTrailing) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Client input")
                .accessibilityIdentifier("client-input")
                .accessibilityActions {
                    Button("Client input") {
                        store.surface?.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
                    }
                    Button("Reattach Client") { store.reattach() }
                    Button("New Window") { store.ghosttyNewTab() }
                }
        }
        #else
        content
        #endif
    }
}
