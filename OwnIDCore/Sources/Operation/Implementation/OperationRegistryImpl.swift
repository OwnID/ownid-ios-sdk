import Foundation

/// Main-actor registry of active operation controllers for one SDK instance.
///
/// Contract:
/// - One `OperationID` corresponds to one operation lifecycle.
/// - That lifecycle must be represented by exactly one controller instance in the registry.
/// - Re-registering a different controller for the same `OperationID` is an invariant violation by the caller.
///
/// Registry updates publish a full active-controller state through ``OperationRegistry/current``. Duplicate
/// registrations are recovery-only and do not relax the owner contract: one ``OperationID`` belongs to one controller
/// lifecycle, and the operation owner unregisters that controller after settlement or cleanup.
internal final class OperationRegistryImpl: OperationRegistry, @unchecked Sendable {
    @MainActor private(set) var operations: [OperationID: any OperationController] = [:]
    @MainActor private var continuations: [UUID: AsyncStream<OperationRegistryState>.Continuation] = [:]
    private let logger: OwnIDLogRouter?

    init(logger: OwnIDLogRouter?) {
        self.logger = logger
    }

    @MainActor
    var current: AsyncStream<OperationRegistryState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(OperationRegistryState(map: operations))

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    @MainActor
    func register(controller: any OperationController) {
        if operations[controller.operationID] != nil {
            logger?.logW(
                source: self,
                prefix: #function,
                message:
                    "Invariant violation: duplicate operation id registration; replacing existing controller for \(controller.operationID)"
            )
        }
        logger?.logD(source: self, prefix: #function, message: "Operation: \(controller.operationID)")
        operations[controller.operationID] = controller
        broadcast()
    }

    @MainActor
    func unregister(id: OperationID) {
        logger?.logD(source: self, prefix: #function, message: "Operation: \(id)")
        operations.removeValue(forKey: id)
        broadcast()
    }

    @MainActor
    private func broadcast() {
        let state = OperationRegistryState(map: operations)
        let sinks = Array(continuations.values)
        for continuation in sinks { continuation.yield(state) }
    }
}
