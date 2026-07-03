import Foundation

internal final class PasskeyAssertionAPIImpl: PasskeyAssertionAPI {
    private let apiBaseURL: any APIBaseURL
    private let network: any NetworkProtocol
    private let coder: any JSONCoder
    private let context: Context?
    private let loginIDValidator: (any LoginIDValidator)?
    private let interceptor: (any APICallInterceptor)?

    internal init(
        apiBaseURL: any APIBaseURL,
        network: any NetworkProtocol,
        coder: any JSONCoder,
        context: Context?,
        loginIDValidator: (any LoginIDValidator)?,
        interceptor: (any APICallInterceptor)?
    ) {
        self.apiBaseURL = apiBaseURL
        self.network = network
        self.coder = coder
        self.context = context
        self.loginIDValidator = loginIDValidator
        self.interceptor = interceptor
    }

    internal func start(
        params: PasskeyAssertionAPIParams?
    ) async -> APIResult<any PasskeyAssertionAPIController, PasskeyAssertionStartAPIFailure> {
        do {
            let accessToken = params?.accessToken ?? context?.accessToken
            let baseUrl = try apiBaseURL.getBaseURL()
            let traceParent = params?.traceParent ?? TraceContext.generateTraceParent()
            let loginID: LoginID?
            if let provided = params?.loginID {
                loginID = provided
            } else {
                loginID = try context?.loginID(loginIDValidator: loginIDValidator)
            }
            let request = try PasskeyAssertionOptionsAPICall(
                apiBaseURL: baseUrl,
                coder: coder,
                loginID: loginID,
                accessToken: accessToken,
                traceParent: traceParent
            )
            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
                .map { assertionOptions in
                    PasskeyAssertionAPIControllerImpl(
                        apiBaseURL: baseUrl,
                        network: network,
                        coder: coder,
                        assertionOptions: assertionOptions,
                        accessToken: accessToken,
                        traceParent: traceParent,
                        interceptor: interceptor
                    )
                }
        } catch is CancellationError {
            return .canceled
        } catch let error as LoginIDResolutionError {
            return .failure(.contextLoginIDFailure(error))
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any PasskeyAssertionAPI {
        do {
            return PasskeyAssertionAPIImpl(
                apiBaseURL: try resolver.getOrThrow(type: (any APIBaseURL).self),
                network: try resolver.getOrThrow(type: (any NetworkProtocol).self),
                coder: try resolver.getOrThrow(type: (any JSONCoder).self),
                context: resolver.getOrNil(type: Context.self),
                loginIDValidator: resolver.getOrNil(type: (any LoginIDValidator).self),
                interceptor: resolver.getOrNil(type: (any APICallInterceptor).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: PasskeyAssertionAPI, @unchecked Sendable {
    private let error: any Error

    internal init(error: any Error) {
        self.error = error
    }

    func start(params: PasskeyAssertionAPIParams?) async -> APIResult<any PasskeyAssertionAPIController, PasskeyAssertionStartAPIFailure> {
        let message = (error as? MissingDependencyError)?.dependencyName ?? String(describing: error)
        return .failure(
            .unexpected(
                errorCode: .unknown,
                message: message,
                underlyingError: APIUnexpectedError(cause: .runtime(error.asSendableError()))
            )
        )
    }
}

extension PasskeyAssertionStartAPIFailure {
    fileprivate static func contextLoginIDFailure(_ error: LoginIDResolutionError) -> PasskeyAssertionStartAPIFailure {
        switch error {
        case .missingLoginIDValidator(_, let message):
            return .failedDependency(
                .missingProvider(errorCode: error.errorCode, message: message, capability: "LoginIdValidator", scope: .data)
            )
        case .loginIDTypeNotSupported(_, let message):
            return .badRequest(.unsupportedLoginIDType(errorCode: error.errorCode, message: message))
        case .loginIDValidation(_, let message, let loginID, let regex):
            return .badRequest(.invalidLoginID(errorCode: error.errorCode, message: message, loginID: loginID, regex: regex))
        }
    }
}
