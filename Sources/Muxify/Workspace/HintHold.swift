import Foundation
import Observation
import MuxifyCore

struct HintHoldState {
    enum Event {
        case modifiers(KeyTrigger.Modifiers)
        case keyDown(UInt16)
        case keyUp(UInt16)
        case reset
    }

    enum Phase: Equatable {
        case idle
        case waiting(KeyTrigger.Modifiers, deadline: TimeInterval)
        case shown(KeyTrigger.Modifiers)
        case suppressed
    }

    private(set) var phase: Phase = .idle
    private var modifiers: KeyTrigger.Modifiers = []
    private var delay: TimeInterval? = 0.35
    private var pressedKeys: Set<UInt16> = []

    var visibleModifiers: KeyTrigger.Modifiers? {
        if case .shown(let modifiers) = phase { return modifiers }
        return nil
    }

    var deadline: TimeInterval? {
        if case .waiting(_, let deadline) = phase { return deadline }
        return nil
    }

    mutating func configure(delay: TimeInterval?, at time: TimeInterval) {
        guard self.delay != delay else { return }
        self.delay = delay
        guard phase != .suppressed else { return }
        phase = .idle
        if !modifiers.isEmpty { receive(.modifiers(modifiers), at: time) }
    }

    mutating func receive(_ event: Event, at time: TimeInterval) {
        switch event {
        case .keyDown(let key):
            pressedKeys.insert(key)
            phase = .suppressed
        case .keyUp(let key):
            pressedKeys.remove(key)
            if pressedKeys.isEmpty && modifiers.isEmpty { phase = .idle }
        case .reset:
            pressedKeys.removeAll()
            phase = modifiers.isEmpty ? .idle : .suppressed
        case .modifiers(let modifiers):
            self.modifiers = modifiers
            if modifiers.isEmpty {
                phase = pressedKeys.isEmpty ? .idle : .suppressed
                return
            }
            switch phase {
            case .suppressed: return
            case .waiting(let held, _), .shown(let held):
                if held == modifiers { return }
            case .idle: break
            }
            guard let delay else { phase = .idle; return }
            phase = delay == 0 ? .shown(modifiers) : .waiting(modifiers, deadline: time + delay)
        }
    }

    mutating func advance(to time: TimeInterval) {
        if case .waiting(let modifiers, let deadline) = phase, time >= deadline {
            phase = .shown(modifiers)
        }
    }
}

@MainActor @Observable final class HintHold {
    private var state = HintHoldState()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    var visibleModifiers: KeyTrigger.Modifiers? { state.visibleModifiers }

    func configure(delay: TimeInterval?) {
        let before = state.phase
        state.configure(delay: delay, at: ProcessInfo.processInfo.systemUptime)
        if state.phase != before { schedule() }
    }

    func receive(_ event: HintHoldState.Event) {
        let before = state.phase
        state.receive(event, at: ProcessInfo.processInfo.systemUptime)
        if state.phase != before { schedule() }
    }

    private func schedule() {
        timer?.cancel()
        let token = UUID()
        generation = token
        guard let deadline = state.deadline else { timer = nil; return }
        timer = Task { [weak self] in
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == token else { return }
            state.advance(to: ProcessInfo.processInfo.systemUptime)
            timer = nil
        }
    }
}
