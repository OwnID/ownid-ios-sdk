import Foundation

/// Base protocol for all OwnID operation runtimes.
///
/// Call ``start(params:)`` to launch the operation and receive a controller, and use ``isAvailable(params:)`` or
/// ``availability(params:)`` to check runtime readiness for the given parameters.
///
/// A runtime object owns a single operation lifecycle. Once ``start(params:)`` moves that runtime out of its initial
/// state, repeated ``start(params:)`` calls on the same object return the same controller and do not restart the
/// operation. Public namespace operation entries create a new runtime object for each launch, so call the namespace
/// entry again when a new operation run is needed.
///
/// Availability is a preflight signal only. ``start(params:)`` revalidates inputs and dependencies and may still
/// settle with ``OperationResult/failure(_:)`` or ``OperationResult/canceled(_:)`` if runtime state changes.
///
/// The caller owns the returned controller. Keep it strongly referenced while the operation is active.
///
/// Use ``OperationController/abort(reason:)`` for semantic cancellation when you have an explicit reason that should
/// be propagated to the terminal result. If the owner is torn down while the operation is still active, abort the
/// operation with an appropriate ``Reason``.
///
/// Cancellation is best-effort. Calling ``OperationController/abort(reason:)`` after settlement is safe and has no
/// effect.
public protocol OperationCapability: Capability {
    associatedtype Params: CapabilityParams
    associatedtype Result: Sendable
    associatedtype Failure: OperationFailure

    var operationType: OperationType { get }

    /// Launches the operation with optional `params`.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the operation is
    /// still active.
    func start(params: Params?) -> any OperationController<Result, Failure>

    /// Returns whether the operation can start with the given `params`.
    ///
    /// Pass `nil` to check availability without explicit parameters. If unavailable, the result carries a diagnostic
    /// message explaining what must change before calling ``start(params:)``.
    func availability(params: (any CapabilityParams)?) async -> Availability
}

/// Marker protocol for operation state types emitted by operation-specific controllers.
///
/// Operation-specific controllers may expose an `AsyncStream` of these states. The stream yields the latest state to a
/// new observer and then emits later transitions while the operation is active. Treat a terminal state and
/// ``OperationController/whenSettled()`` as completion signals; the stream is not a one-shot completion channel.
public protocol OperationState: Sendable {}

/// Marker protocol for SDK UI capabilities that can present or bind operation state.
public protocol OperationUI: Capability, Sendable {}

extension OperationCapability {
    public func start() -> any OperationController<Result, Failure> {
        start(params: nil)
    }

    public func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        if case .available = await availability(params: params) { return true }
        return false
    }
}

/// Result of a completed operation.
///
/// Every operation finishes with exactly one of ``success(_:)``, ``canceled(_:)``, or ``failure(_:)``.
/// ``canceled(_:)`` carries a ``Reason`` and is separate from failure handling. ``failure(_:)`` carries a typed
/// ``OperationFailure`` with diagnostic text and a message lookup key.
public enum OperationResult<Success: Sendable, Failure: OperationFailure>: Sendable, CustomStringConvertible {
    case success(Success)
    case canceled(Reason)
    case failure(Failure)

    public var description: String {
        switch self {
        case .success: return "Success"
        case .canceled(let reason): return "Canceled(reason=\(reason))"
        case .failure(let failure): return "Failure(failure=\(failure))"
        }
    }
}

/// Failure payload returned by completed operations.
///
/// The concrete operation failure type identifies the semantic reason the operation stopped. Callers should branch on
/// the operation's typed failure enum when deciding the next step, such as keeping the current surface open, showing an
/// error, offering another method, retrying later, or ending the current interaction.
///
/// ``message`` is diagnostic text from the backend, SDK, or provider path. It is not localized end-user copy. Operation
/// UI state uses ``UIError`` for user-facing text. ``errorCode`` is a localization key, not the semantic failure
/// contract. Code that shows an OwnID error should map the failure to owned copy or call
/// ``ErrorCode/toLocalizedMessage(instanceName:fallbackErrorStrings:)`` when the SDK default text is appropriate.
public protocol OperationFailure: Sendable {
    /// Localization key for resolving failure text.
    var errorCode: ErrorCode { get }
    /// Diagnostic message associated with the failure.
    var message: String { get }
}

extension OperationFailure {
    /// Returns a UI-ready error for this operation failure.
    ///
    /// The returned ``UIError`` uses this failure's ``OperationFailure/errorCode``. The message is resolved from the
    /// OwnID strings available for `instanceName`, or from `fallbackErrorStrings` when the instance has no message for
    /// this code. This conversion is only for display text; it does not change the typed failure that operation owners
    /// should branch on.
    public func toUIError(
        instanceName: InstanceName = .default,
        fallbackErrorStrings: ErrorStrings = .default
    ) -> UIError {
        UIError(
            errorCode: errorCode,
            localizedMessage: errorCode.toLocalizedMessage(instanceName: instanceName, fallbackErrorStrings: fallbackErrorStrings)
        )
    }
}

extension OperationResult {
    @discardableResult
    public func onSuccess(_ action: (Success) -> Void) -> Self {
        if case .success(let success) = self { action(success) }
        return self
    }

    @discardableResult
    public func onCanceled(_ action: (Reason) -> Void) -> Self {
        if case .canceled(let reason) = self { action(reason) }
        return self
    }

    @discardableResult
    public func onError(_ action: (Failure) -> Void) -> Self {
        if case .failure(let failure) = self { action(failure) }
        return self
    }

    public func fold<T>(
        onSuccess: (Success) -> T,
        onCanceled: (Reason) -> T,
        onError: (Failure) -> T
    ) -> T {
        switch self {
        case .success(let success): return onSuccess(success)
        case .canceled(let reason): return onCanceled(reason)
        case .failure(let failure): return onError(failure)
        }
    }

    public func map<T: Sendable>(_ transform: (Success) -> T) -> OperationResult<T, Failure> {
        switch self {
        case .success(let success): return .success(transform(success))
        case .canceled(let reason): return .canceled(reason)
        case .failure(let failure): return .failure(failure)
        }
    }

    public func getOrNil() -> Success? {
        switch self {
        case .success(let success): return success
        case .canceled, .failure: return nil
        }
    }

    public func errorOrNil() -> Failure? {
        switch self {
        case .failure(let failure): return failure
        case .success, .canceled: return nil
        }
    }

    public func reasonOrNil() -> Reason? {
        switch self {
        case .canceled(let reason): return reason
        case .success, .failure: return nil
        }
    }
}

/// Controls one active operation lifecycle.
///
/// Use ``operationID`` to identify the running operation and ``whenSettled()`` to await its terminal
/// ``OperationResult``. A controller represents exactly one started operation and always settles once with
/// ``OperationResult/success(_:)``, ``OperationResult/canceled(_:)``, or ``OperationResult/failure(_:)``.
public protocol OperationController<Success, Failure>: Sendable {
    associatedtype Success: Sendable
    associatedtype Failure: OperationFailure

    /// Unique identifier for this operation instance.
    var operationID: OperationID { get }

    /// Requests operation cancellation with an explicit reason.
    ///
    /// Use this API when cancellation semantics are meaningful to the caller and should be reflected in the terminal
    /// result. Cancellation is best-effort; a request made after settlement does not change the terminal result.
    func abort(reason: Reason)

    /// Awaits the operation's completion and returns the typed ``OperationResult``.
    ///
    /// Multiple owners may await the same controller. After settlement, this function returns the stored terminal
    /// result immediately. Use ``abort(reason:)`` to request operation cancellation; canceling a task that is only
    /// waiting here does not define the operation's terminal ``OperationResult``.
    func whenSettled() async -> OperationResult<Success, Failure>
}

/// Base controller storage for operation implementations.
///
/// Operation runtimes own settlement and call exactly one of `complete(_:)`, `cancel(_:)`, or `fail(_:)`. Awaiters only
/// observe the stored terminal ``OperationResult``; canceling a task that is waiting in ``whenSettled()`` is not an
/// operation cancellation API. The optional owner hold keeps a single-run runtime alive until settlement releases it.
internal class OperationControllerImpl<Success: Sendable, Failure: OperationFailure>: OperationController, @unchecked Sendable {
    private actor Storage {
        private var continuations: [CheckedContinuation<OperationResult<Success, Failure>, Never>] = []
        private var cached: OperationResult<Success, Failure>?

        fileprivate func awaitResult() async -> OperationResult<Success, Failure> {
            if let cached { return cached }
            return await withCheckedContinuation { continuations.append($0) }
        }

        fileprivate func resolve(with result: OperationResult<Success, Failure>) {
            guard cached == nil else { return }
            cached = result
            let toResume = continuations
            continuations.removeAll()
            for c in toResume {
                c.resume(returning: result)
            }
        }
    }

    private let ownerStrongHoldLock = NSLock()
    private var _ownerStrongHold: AnyObject?
    internal let operationID: OperationID
    private let onUserAborted: @Sendable (Reason) -> Void
    private let storage = Storage()

    internal func _attachOwner(_ owner: AnyObject) {
        ownerStrongHoldLock.withLock { _ownerStrongHold = owner }
    }

    internal func _releaseOwner() {
        ownerStrongHoldLock.withLock { _ownerStrongHold = nil }
    }

    internal init(operationID: OperationID, onUserAborted: @escaping @Sendable (Reason) -> Void) {
        self.operationID = operationID
        self.onUserAborted = onUserAborted
    }

    internal func abort(reason: Reason) {
        onUserAborted(reason)
    }

    internal func whenSettled() async -> OperationResult<Success, Failure> {
        await storage.awaitResult()
    }

    internal func complete(_ success: Success) {
        ownerStrongHoldLock.withLock { _ownerStrongHold = nil }
        Task { await storage.resolve(with: .success(success)) }
    }

    internal func cancel(_ reason: Reason) {
        ownerStrongHoldLock.withLock { _ownerStrongHold = nil }
        Task { await storage.resolve(with: .canceled(reason)) }
    }

    internal func fail(_ failure: Failure) {
        ownerStrongHoldLock.withLock { _ownerStrongHold = nil }
        Task { await storage.resolve(with: .failure(failure)) }
    }
}
