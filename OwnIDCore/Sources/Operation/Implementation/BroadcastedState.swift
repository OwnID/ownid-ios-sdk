import Foundation

/// Stores operation state and broadcasts replacement states to observers.
///
/// New observers receive the current state immediately, then every later assigned state. Operation controllers expose
/// these streams across module boundaries; consumers should treat each value as the latest complete state, not as a
/// delta or completion signal. The wrapped value and its sinks must be accessed from the owning actor; operation
/// controllers keep that boundary on `MainActor`.
@propertyWrapper
internal final class BroadcastedState<State: Sendable>: @unchecked Sendable {
    private var value: State
    private var sinks: [UUID: AsyncStream<State>.Continuation] = [:]

    init(wrappedValue: State) {
        self.value = wrappedValue
    }

    var wrappedValue: State {
        get { value }
        set {
            value = newValue
            for continuation in sinks.values { continuation.yield(newValue) }
        }
    }

    @MainActor
    func stream() -> AsyncStream<State> {
        let current = value
        let id = UUID()
        return AsyncStream { continuation in
            sinks[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.sinks.removeValue(forKey: id) }
            }
        }
    }
}
