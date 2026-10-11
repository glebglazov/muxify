import SwiftUI
import MuxifyCore

struct HintVerification: ViewModifier {
    let store: WorkspaceStore

    func body(content: Content) -> some View {
        #if DEBUG
        content.overlay(alignment: .bottomTrailing) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hint input")
                .accessibilityIdentifier("quick-switch-input")
                .accessibilityActions {
                    Button("Hold Control") { store.receiveHintInput(.modifiers(.control)) }
                    Button("Hold Command") { store.receiveHintInput(.modifiers(.command)) }
                    Button("Hold Option") { store.receiveHintInput(.modifiers(.option)) }
                    Button("Hold Control Command") { store.receiveHintInput(.modifiers([.control, .command])) }
                    Button("Release modifiers") { store.receiveHintInput(.modifiers([])) }
                    Button("Other key") {
                        store.receiveHintInput(.keyDown(0))
                        store.receiveHintInput(.keyUp(0))
                    }
                    Button("Reset Hints") { store.receiveHintInput(.reset) }
                    ForEach(ConfigAction.allCases.filter { $0.quickSwitchSelection != nil || $0 == .moveKeyboardToTerminal }, id: \.self) { action in
                        ForEach(store.config.keybinds.triggers[action] ?? [], id: \.self) { trigger in
                            Button("Press " + trigger.symbol) {
                                store.receiveHintInput(.keyDown(0))
                                store.performConfiguredShortcut(trigger)
                                store.receiveHintInput(.keyUp(0))
                            }
                        }
                    }
                }
        }
        #else
        content
        #endif
    }
}
