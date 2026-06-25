import Foundation

/// Base protocol for direct OwnID APIs.
///
/// API capabilities expose direct OwnID operations that complete with typed ``APIResult`` values. Callers own the
/// returned result: handle ``APIResult/success(_:)`` for endpoint payloads, ``APIResult/failure(_:)`` for the
/// endpoint-specific failure model, and ``APIResult/canceled`` for Swift task cancellation.
public protocol APICapability: Capability, Sendable {}

/// Result of a direct OwnID API call.
///
/// ``success(_:)`` carries the endpoint payload. ``failure(_:)`` carries an endpoint-specific ``APIFailure`` value.
/// Each endpoint defines the failures that app code can branch on, including its `unexpected` case for failures that
/// are not an endpoint-defined business response.
///
/// If the surrounding Swift task is canceled before the call completes, public direct APIs return ``canceled``.
public enum APIResult<Success: Sendable, Failure: Sendable>: Sendable, CustomStringConvertible {
    case success(Success)
    case failure(Failure)
    case canceled

    public var description: String {
        switch self {
        case .success: return "Success"
        case .failure(let failure): return "Failure(failure=\(String(describing: failure)))"
        case .canceled: return "Canceled"
        }
    }
}

/// Failure payload returned by direct API calls.
///
/// Branch on the endpoint-specific failure value when deciding the app's next step, such as keeping the current screen
/// open, showing an error, offering another method, retrying later, or ending the flow. Expected endpoint failures and
/// endpoint `unexpected` failures both expose this shared error shape.
///
/// ``message`` is diagnostic text from the backend or SDK. It is not localized end-user copy. When the app shows an
/// OwnID error to the user, ``errorCode`` is the localization key to map to app copy or pass to
/// ``ErrorCode/toLocalizedMessage(instanceName:fallbackErrorStrings:)`` when the SDK default text is appropriate for
/// that screen.
public protocol APIFailure: Sendable {
    /// Localization key for resolving failure text.
    var errorCode: ErrorCode { get }
    /// Diagnostic message associated with the failure.
    var message: String { get }
}

extension APIFailure {
    /// Returns a UI-ready error for this API failure.
    ///
    /// The returned ``UIError`` uses this failure's ``APIFailure/errorCode``. The message is resolved from the OwnID
    /// strings available for `instanceName`, or from `fallbackErrorStrings` when the instance has no message for this
    /// code. The diagnostic ``APIFailure/message`` is not used as end-user copy.
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

/// Backend dependency scope reported by provider or capability dependency failures.
public enum APIFailureScope: String, Codable, CaseIterable, Sendable {
    case data

    case channel

    case session
}

extension APIResult {
    @discardableResult
    public func onSuccess(_ action: (Success) -> Void) -> Self {
        if case .success(let success) = self { action(success) }
        return self
    }

    @discardableResult
    public func onError(_ action: (Failure) -> Void) -> Self {
        if case .failure(let error) = self { action(error) }
        return self
    }

    @discardableResult
    public func onCanceled(_ action: () -> Void) -> Self {
        if case .canceled = self { action() }
        return self
    }

    public func fold<T>(
        onSuccess: (Success) -> T,
        onError: (Failure) -> T,
        onCanceled: () -> T
    ) -> T {
        switch self {
        case .success(let success): return onSuccess(success)
        case .failure(let error): return onError(error)
        case .canceled: return onCanceled()
        }
    }

    public func map<T: Sendable>(_ transform: (Success) -> T) -> APIResult<T, Failure> {
        switch self {
        case .success(let success): return .success(transform(success))
        case .failure(let error): return .failure(error)
        case .canceled: return .canceled
        }
    }

    public func mapError<NewFailure: Sendable>(_ transform: (Failure) -> NewFailure) -> APIResult<Success, NewFailure> {
        switch self {
        case .success(let success): return .success(success)
        case .failure(let error): return .failure(transform(error))
        case .canceled: return .canceled
        }
    }

    public func getOrNil() -> Success? {
        switch self {
        case .success(let success): return success
        case .failure, .canceled: return nil
        }
    }

    public func errorOrNil() -> Failure? {
        switch self {
        case .success, .canceled: return nil
        case .failure(let error): return error
        }
    }

    public var isCanceled: Bool {
        if case .canceled = self { return true }
        return false
    }
}
