import Foundation

internal final class OIDCAPIImpl: OIDCAPI {
    private let apiBaseURL: any APIBaseURL
    private let network: any NetworkProtocol
    private let coder: any JSONCoder
    private let context: Context?
    private let interceptor: (any APICallInterceptor)?

    internal init(
        apiBaseURL: any APIBaseURL,
        network: any NetworkProtocol,
        coder: any JSONCoder,
        context: Context?,
        interceptor: (any APICallInterceptor)?
    ) {
        self.apiBaseURL = apiBaseURL
        self.network = network
        self.coder = coder
        self.context = context
        self.interceptor = interceptor
    }

    internal func start(params: OIDCAPIParams?) async -> APIResult<any OIDCAPIController, OIDCStartAPIFailure> {
        do {
            let baseUrl = try apiBaseURL.getBaseURL()
            let accessToken = params?.accessToken ?? context?.accessToken
            let traceParent = params?.traceParent ?? TraceContext.generateTraceParent()
            let expectedResponseType = params?.oauthResponseType ?? .idToken
            let request = try OIDCStartAPICall(
                apiBaseURL: baseUrl,
                coder: coder,
                provider: params?.provider ?? .apple,
                oauthResponseType: expectedResponseType,
                accessToken: accessToken,
                traceParent: traceParent
            )

            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
                .map { challenge in
                    OIDCAPIControllerImpl(
                        apiBaseURL: baseUrl,
                        coder: coder,
                        network: network,
                        challenge: challenge,
                        accessToken: accessToken,
                        traceParent: traceParent,
                        expectedResponseType: expectedResponseType,
                        interceptor: interceptor
                    )
                }
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any OIDCAPI {
        do {
            return OIDCAPIImpl(
                apiBaseURL: try resolver.getOrThrow(type: (any APIBaseURL).self),
                network: try resolver.getOrThrow(type: (any NetworkProtocol).self),
                coder: try resolver.getOrThrow(type: (any JSONCoder).self),
                context: resolver.getOrNil(type: Context.self),
                interceptor: resolver.getOrNil(type: (any APICallInterceptor).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: OIDCAPI, @unchecked Sendable {
    private let error: any Error

    internal init(error: any Error) {
        self.error = error
    }

    func start(params: OIDCAPIParams?) async -> APIResult<any OIDCAPIController, OIDCStartAPIFailure> {
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
