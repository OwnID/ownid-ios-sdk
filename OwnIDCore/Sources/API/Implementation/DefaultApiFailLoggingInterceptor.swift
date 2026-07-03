import Foundation

/// Default API interceptor that reports unexpected API contract failures to ``ServerLogger``.
///
/// Only SDK-detected API contract mismatches are reported. Business failures, transport failures, and local runtime
/// failures pass through unchanged without server logging. Logging is best-effort and never changes the API result
/// returned to the caller.
internal final class DefaultApiFailLoggingInterceptor: APICallInterceptor, @unchecked Sendable {
    private let serverLoggerProvider: () -> ServerLogger?

    internal init(serverLoggerProvider: @escaping () -> ServerLogger?) {
        self.serverLoggerProvider = serverLoggerProvider
    }

    /// Logs unexpected mapped API contract failures and returns the original response unchanged.
    internal func onResponse<APISuccess: Sendable, APIFailureValue: Sendable>(
        request: NetworkRequest,
        response: APIResult<APISuccess, APIFailureValue>
    ) async -> APIResult<APISuccess, APIFailureValue> {
        guard case .failure(let failure) = response else { return response }
        guard let apiFailure = failure as? any APIFailure else { return response }
        guard let unexpectedError = unexpectedErrorOrNil(failure) else { return response }
        guard case .apiContract(let contract) = unexpectedError.cause else { return response }
        guard let serverLogger = serverLoggerProvider() else { return response }

        let httpCode: Int?
        let underlyingError: (any Error)?
        switch contract.failure {
        case .httpError(let httpError):
            httpCode = httpError.statusCode
            underlyingError = contract.error
        case .networkError:
            httpCode = nil
            underlyingError = contract.error
        case .responseError(let responseError):
            httpCode = responseError.statusCode
            underlyingError = contract.error ?? responseError.error
        }

        var message =
            "Unexpected APIResult.failure, method=\(request.method.rawValue), url=\(request.url), errorCode=\(apiFailure.errorCode.value)"
        if let httpCode {
            message += ", httpCode=\(httpCode)"
        }
        if !apiFailure.message.isEmpty {
            message += ", message=\(apiFailure.message)"
        }

        serverLogger.log(
            level: .error,
            className: "DefaultApiFailLoggingInterceptor",
            message: message,
            cause: underlyingError
        )

        return response
    }

    private func unexpectedErrorOrNil(_ failure: Any) -> APIUnexpectedError? {
        switch failure {
        case let failure as DiscoverAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as OIDCStartAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as OIDCCompleteAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as OIDCCancelAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as EmailVerificationStartAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as EmailVerificationCompleteAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as EmailVerificationResendAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as EmailVerificationCancelAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PhoneVerificationStartAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PhoneVerificationCompleteAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PhoneVerificationResendAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PhoneVerificationCancelAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PasskeyEnrollAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as EmailEnrollAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PhoneEnrollAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as LoginAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as AppConfigFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PasskeyAttestationStartAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PasskeyAttestationVerifyAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PasskeyAttestationCancelAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PasskeyAssertionStartAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PasskeyAssertionVerifyAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as PasskeyAssertionCancelAPIFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        case let failure as EventsFailure:
            if case .unexpected(_, _, let error) = failure { return error as? APIUnexpectedError }
        default:
            break
        }
        return nil
    }
}
