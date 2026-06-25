import Foundation

internal final class PhoneEnrollAPIImpl: PhoneEnrollAPI {
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

    internal func start(params: PhoneEnrollAPIParams) async -> APIResult<Void, PhoneEnrollAPIFailure> {
        do {
            guard let accessToken = params.accessToken ?? context?.accessToken else {
                return .failure(.badRequest(.invalidArgument(errorCode: .invalidArgument, message: "AccessToken is required")))
            }

            let request = try PhoneEnrollAPICall(
                apiBaseURL: try apiBaseURL.getBaseURL(),
                coder: coder,
                proofToken: params.proofToken,
                accessToken: accessToken,
                traceParent: params.traceParent ?? TraceContext.generateTraceParent(),
            )
            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any PhoneEnrollAPI {
        do {
            return PhoneEnrollAPIImpl(
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

private final class Failed: PhoneEnrollAPI, @unchecked Sendable {
    private let error: any Error

    internal init(error: any Error) {
        self.error = error
    }

    func start(params: PhoneEnrollAPIParams) async -> APIResult<Void, PhoneEnrollAPIFailure> {
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
