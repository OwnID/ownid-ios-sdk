import Foundation

/// Marker protocol for SDK capabilities that orchestrate authentication flows.
///
/// Flows sit above direct APIs and operations: they choose the required operations, forward SDK context and provider
/// callbacks, and settle once with a ``FlowResult``.
public protocol FlowCapability: Capability {}

/// Outcome of an authentication flow.
///
/// A settled flow has exactly one terminal result: ``success(_:)``, ``canceled(_:)``, or ``failure(_:)``. Flow
/// controllers return the cached terminal result after settlement, so repeated `whenSettled()` calls observe the same
/// value.
///
/// ``canceled(_:)`` represents an intentional stop with a ``Reason``, such as user close, timeout, or system-level
/// cancellation. ``failure(_:)`` represents a handled flow error with a typed ``FlowFailure`` payload. Use the specific
/// result case instead of inferring cancellation or failure from messages or error codes.
public enum FlowResult<Success: Sendable, Failure: FlowFailure>: Sendable, CustomStringConvertible {
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

/// Failure payload returned by completed flows.
///
/// Concrete flow failure types are declared by each flow. Branch on the flow-specific failure enum when deciding the
/// app's next step. Failure payloads are distinct from ``FlowResult/canceled(_:)``, which carries a ``Reason`` and does
/// not contain a ``FlowFailure``.
///
/// ``message`` is diagnostic text from the backend, SDK, or provider path. It is not localized end-user copy. When the
/// app shows an OwnID error to the user, map ``errorCode`` to app copy or call
/// ``ErrorCode/toLocalizedMessage(instanceName:fallbackErrorStrings:)`` when the SDK default text is appropriate for
/// that screen. ``errorCode`` is a localization key, not the semantic failure contract.
public protocol FlowFailure: Sendable {
    /// Localization key for resolving failure text.
    var errorCode: ErrorCode { get }
    /// Diagnostic message associated with the failure.
    var message: String { get }
}

extension FlowFailure {
    /// Returns a UI-ready error for this flow failure.
    ///
    /// The returned ``UIError`` uses this failure's ``FlowFailure/errorCode``. The message is resolved from the OwnID
    /// strings available for `instanceName`, or from `fallbackErrorStrings` when the instance has no message for this
    /// code. The diagnostic ``FlowFailure/message`` is not copied into the UI error.
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

extension FlowResult {
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

    public func map<T: Sendable>(_ transform: (Success) -> T) -> FlowResult<T, Failure> {
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

// Invariant: a controller accepts one start and publishes one terminal result; cancellation after settlement cannot
// replace that result.
internal final class FlowController<Success: Sendable, Failure: FlowFailure>: @unchecked Sendable {
    private actor Storage {
        private var continuations: [CheckedContinuation<FlowResult<Success, Failure>, Never>] = []
        private var cached: FlowResult<Success, Failure>?

        fileprivate func awaitResult() async -> FlowResult<Success, Failure> {
            if let cached { return cached }
            return await withCheckedContinuation { continuations.append($0) }
        }

        fileprivate func resolve(with result: FlowResult<Success, Failure>) {
            guard cached == nil else { return }
            cached = result
            let toResume = continuations
            continuations.removeAll()
            for c in toResume {
                c.resume(returning: result)
            }
        }
    }

    private var _ownerStrongHold: AnyObject?
    private let onUserAborted: @Sendable (Reason) -> Void
    private let storage = Storage()
    private let startAcceptedLock = NSLock()
    private var startAccepted = false

    internal init(onUserAborted: @escaping @Sendable (Reason) -> Void) {
        self.onUserAborted = onUserAborted
    }

    internal func _attachOwner(_ owner: AnyObject) { _ownerStrongHold = owner }

    internal func _releaseOwner() { _ownerStrongHold = nil }

    internal func abort(reason: Reason) {
        onUserAborted(reason)
    }

    internal func whenSettled() async -> FlowResult<Success, Failure> {
        await storage.awaitResult()
    }

    internal func _acceptStart() -> Bool {
        startAcceptedLock.withLock {
            if startAccepted { return false }
            startAccepted = true
            return true
        }
    }

    internal func complete(_ success: Success) {
        _ownerStrongHold = nil
        Task { await storage.resolve(with: .success(success)) }
    }

    internal func cancel(_ reason: Reason) {
        _ownerStrongHold = nil
        Task { await storage.resolve(with: .canceled(reason)) }
    }

    internal func fail(_ failure: Failure) {
        _ownerStrongHold = nil
        Task { await storage.resolve(with: .failure(failure)) }
    }
}
