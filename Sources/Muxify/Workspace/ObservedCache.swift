import Foundation
import Observation

/// A value built from observable state and kept until that state changes, or until the time its `expiry` returns.
/// For a value that views read many times in each update and that is expensive to build.
///
/// `withObservationTracking` reports a change before the new state is stored. A view can update at that moment and
/// read the value: the build then reads the old state, and its tracking starts after the change, so nothing would
/// drop it. A value built while a change is reported is therefore dropped again on the next turn of the main queue,
/// when the new state is stored.
@MainActor @Observable
final class ObservedCache<Value> {
    @ObservationIgnored private let build: () -> Value
    @ObservationIgnored private let expiry: (Value) -> Date?
    @ObservationIgnored private var cached: Value?
    @ObservationIgnored private var changing = false
    @ObservationIgnored private var builtWhileChanging = false
    /// Readers observe this in place of the state, because a read from the cache reads no state.
    private var generation = 0

    init(expiry: @escaping (Value) -> Date? = { _ in nil }, build: @escaping () -> Value) {
        self.build = build
        self.expiry = expiry
    }

    var value: Value {
        _ = generation
        if let cached, expiry(cached).map({ Date() < $0 }) ?? true { return cached }
        let value = withObservationTracking(build) { [weak self] in
            MainActor.assumeIsolated { self?.invalidate() }
        }
        cached = value
        if changing { builtWhileChanging = true }
        return value
    }

    /// `changing` is set before `generation` changes, because the readers of `generation` can read `value` at once.
    private func invalidate() {
        cached = nil
        if !changing {
            changing = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                changing = false
                guard builtWhileChanging else { return }
                builtWhileChanging = false
                cached = nil
                generation &+= 1
            }
        }
        generation &+= 1
    }
}
