import Foundation

/// Tracks active operation controllers for one SDK instance.
///
/// This is an internal cross-module contract for operation owners and SDK-owned UI hosts. Operation owners register a
/// controller when an operation starts and unregister it after settlement or cleanup. UI hosts observe ``current`` to
/// find controllers they present, but the operation owner remains responsible for settlement and registry cleanup.
/// Registration is a discovery handoff only; hosts must not treat registry removal as a cancellation request or terminal
/// operation result.
///
/// A single ``OperationID`` represents one operation lifecycle. Reusing an ID for a different live controller is an
/// invariant violation by the operation owner. The current implementation may defensively replace the entry to keep the
/// registry usable, but that behavior is recovery-only and not part of the contract.
@_spi(OwnIDInternal) public protocol OperationRegistry: AnyObject, Sendable {
    /// Current active operation controllers on the main actor.
    ///
    /// The `AsyncStream` yields the latest registry state to a new observer and then emits a new full replacement state
    /// when an operation owner registers or unregisters a controller. Observers should keep any presentation lifecycle
    /// tied to the controller they resolved.
    @MainActor var current: AsyncStream<OperationRegistryState> { get }
}

/// Snapshot of all active operations in the registry.
///
/// ``map`` contains the full active-controller map for that emission, keyed by ``OperationID``.
@MainActor
@_spi(OwnIDInternal) public struct OperationRegistryState {
    /// The current map of active operation controllers, keyed by ``OperationID``.
    public let map: [OperationID: any OperationController]

    internal init(map: [OperationID: any OperationController]) {
        self.map = map
    }
}
