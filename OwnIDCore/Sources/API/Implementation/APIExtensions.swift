import Foundation

extension Error {
    internal func asSendableError() -> any Error & Sendable {
        return self as NSError
    }

    /// Maps a local SDK exception into the endpoint's unexpected failure type.
    ///
    /// Public API wrappers use this for local setup or execution failures that are not cancellation.
    internal func toAPIUnexpectedFailure<Failure>(_ create: (ErrorCode, String, any Error & Sendable) -> Failure) -> Failure {
        let sendableError = asSendableError()
        return create(.unknown, String(describing: self), APIUnexpectedError(cause: .runtime(sendableError)))
    }
}

extension NetworkResponse.Success {
    internal func toUnexpectedStatusFail() -> NetworkResponse.Fail {
        toSuccessMappingFail(message: "Unexpected status code: \(code)")
    }

    internal func toSuccessMappingFail(message: String, cause: (any Error)? = nil) -> NetworkResponse.Fail {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let cause {
            userInfo[NSUnderlyingErrorKey] = cause
        }

        let error = NSError(domain: "OwnID.API", code: code, userInfo: userInfo)
        return .responseError(.init(url: url, statusCode: code, error: error, headers: headers, body: body))
    }
}

extension NetworkResponse.Fail {
    internal var apiFailureMessage: String {
        if case .responseError(let responseError) = self {
            return (responseError.error as NSError).localizedDescription
        }
        return String(describing: self)
    }

    /// Maps a network-layer failure into the endpoint's unexpected failure type.
    ///
    /// Transport failures surface as ``ErrorCode/network``. Unmapped endpoint or response-shape failures surface as
    /// ``ErrorCode/unknown`` because they cannot be represented by a more specific typed failure.
    internal func toUnexpectedFailure<Failure>(
        _ create: (ErrorCode, String, any Error & Sendable) -> Failure,
        error: (any Error)? = nil
    ) -> Failure {
        switch self {
        case .networkError(let networkError):
            return create(.network, String(describing: self), APIUnexpectedError(cause: .network(networkError)))
        case .httpError:
            let sendableError = error?.asSendableError()
            return create(
                .unknown,
                error.map { ($0 as? LocalizedError)?.errorDescription ?? String(describing: $0) } ?? apiFailureMessage,
                APIUnexpectedError(cause: .apiContract(.init(failure: self, error: sendableError)))
            )
        case .responseError(let responseError):
            let sendableError = error?.asSendableError() ?? responseError.error
            return create(
                .unknown,
                error.map { ($0 as? LocalizedError)?.errorDescription ?? String(describing: $0) } ?? String(describing: sendableError),
                APIUnexpectedError(cause: .apiContract(.init(failure: self, error: sendableError)))
            )
        }
    }
}

extension NetworkResponse.Fail.HttpError {
    internal func toUnexpectedFailure<Failure>(
        _ create: (ErrorCode, String, any Error & Sendable) -> Failure,
        error: (any Error)? = nil
    ) -> Failure {
        NetworkResponse.Fail.httpError(self).toUnexpectedFailure(create, error: error)
    }

    internal func mapDecodedBody<Body: Decodable, Failure>(
        coder: any JSONCoder,
        as type: Body.Type,
        unexpected: (ErrorCode, String, any Error & Sendable) -> Failure,
        map: (Body) -> Failure
    ) -> Failure {
        do {
            return map(try coder.decodeFromString(body, as: type))
        } catch {
            return toUnexpectedFailure(unexpected, error: error)
        }
    }

    internal func toForbiddenErrorFailure<Failure>(
        _ create: (ErrorCode, String) -> Failure,
        unexpected: (ErrorCode, String, any Error & Sendable) -> Failure,
        error: any Error
    ) -> Failure {
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return create(.forbidden, String(describing: NetworkResponse.Fail.httpError(self)))
        }
        return toUnexpectedFailure(unexpected, error: error)
    }
}

extension InternalErrorCode {
    internal func toDomainModel() -> ErrorCode {
        ErrorCode(rawValue: rawValue) ?? .unknown
    }
}

extension InternalLoginId {
    internal func toDomainModel() -> LoginID {
        LoginID(id: id, type: type.toDomainModel())
    }
}

extension InternalLoginIdType {
    internal func toDomainModel() -> LoginIDType {
        switch self {
        case .anonymous: return .anonymous
        case .userName: return .userName
        case .email: return .email
        case .phoneNumber: return .phoneNumber
        case .credentialId: return .credentialID
        case .faceKeyPersonId: return .faceKeyPersonID
        }
    }
}

extension LoginIDType {
    internal func toInternalModel() -> InternalLoginIdType {
        switch self {
        case .userName: return .userName
        case .email: return .email
        case .phoneNumber: return .phoneNumber
        case .credentialID: return .credentialId
        case .anonymous: return .anonymous
        case .faceKeyPersonID: return .faceKeyPersonId
        }
    }
}

extension InternalOperationType {
    internal func toDomainModel() -> OperationType {
        switch self {
        case .loginIdCollect: return .loginIDCollect
        case .emailVerification: return .emailVerification
        case .emailEnrollment: return .emailEnrollment
        case .phoneNumberVerification: return .phoneNumberVerification
        case .phoneNumberEnrollment: return .phoneNumberEnrollment
        case .passkeyCreation: return .passkeyCreation
        case .passkeyAuth: return .passkeyAuth
        case .passkeyEnrollment: return .passkeyEnrollment
        case .sessionCreation: return .sessionCreation
        case .deferredAuthentication: return .deferredAuthentication
        case .externalAuthentication: return .externalAuthentication
        case .profileCollection: return .profileCollection
        case .passwordAuthentication: return .passwordAuthentication
        case .oidcAuthenticationApple: return .oidcAuthenticationApple
        case .oidcAuthenticationGoogle: return .oidcAuthenticationGoogle
        case .registration: return .registration
        case .profileUpdate: return .profileUpdate
        case .sessionManagement: return .sessionManagement
        case .webBridge: return .webBridge
        case .faceKeyVerification: return .faceKeyVerification
        case .faceKeyCreation: return .faceKeyCreation
        case .faceKeyEnrollment: return .faceKeyEnrollment
        }
    }
}

extension OperationType {
    internal func toInternalModel() -> InternalOperationType {
        switch self {
        case .loginIDCollect: return .loginIdCollect
        case .emailVerification: return .emailVerification
        case .emailEnrollment: return .emailEnrollment
        case .phoneNumberVerification: return .phoneNumberVerification
        case .phoneNumberEnrollment: return .phoneNumberEnrollment
        case .passkeyCreation: return .passkeyCreation
        case .passkeyAuth: return .passkeyAuth
        case .passkeyEnrollment: return .passkeyEnrollment
        case .sessionCreation: return .sessionCreation
        case .deferredAuthentication: return .deferredAuthentication
        case .externalAuthentication: return .externalAuthentication
        case .profileCollection: return .profileCollection
        case .passwordAuthentication: return .passwordAuthentication
        case .oidcAuthenticationApple: return .oidcAuthenticationApple
        case .oidcAuthenticationGoogle: return .oidcAuthenticationGoogle
        case .registration: return .registration
        case .profileUpdate: return .profileUpdate
        case .sessionManagement: return .sessionManagement
        case .webBridge: return .webBridge
        case .faceKeyVerification: return .faceKeyVerification
        case .faceKeyCreation: return .faceKeyCreation
        case .faceKeyEnrollment: return .faceKeyEnrollment
        }
    }
}

extension InternalScopeType {
    internal func toDomainModel() -> APIFailureScope {
        switch self {
        case .data: return .data
        case .channel: return .channel
        case .session: return .session
        }
    }
}

internal final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    internal func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
