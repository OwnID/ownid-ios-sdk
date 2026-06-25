import Foundation

// Not a part of DI, created internally by AppConfigProvider
internal final class AppConfigAPIImpl: AppConfigAPI {
    private let apiBaseURL: any APIBaseURL
    private let network: any NetworkProtocol
    private let coder: any JSONCoder
    private let interceptor: (any APICallInterceptor)?

    internal init(
        apiBaseURL: any APIBaseURL,
        network: any NetworkProtocol,
        coder: any JSONCoder,
        interceptor: (any APICallInterceptor)?
    ) {
        self.apiBaseURL = apiBaseURL
        self.network = network
        self.coder = coder
        self.interceptor = interceptor
    }

    internal func start(params: AppConfigAPIParams?) async -> APIResult<AppConfig, AppConfigFailure> {
        do {
            let request = try AppConfigAPICall(
                apiBaseURL: try apiBaseURL.getBaseURL(),
                coder: coder,
                traceParent: params?.traceParent ?? TraceContext.generateTraceParent()
            )
            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any AppConfigAPI {
        do {
            return AppConfigAPIImpl(
                apiBaseURL: try resolver.getOrThrow(type: (any APIBaseURL).self),
                network: try resolver.getOrThrow(type: (any NetworkProtocol).self),
                coder: try resolver.getOrThrow(type: (any JSONCoder).self),
                interceptor: resolver.getOrNil(type: (any APICallInterceptor).self)
            )
        } catch {
            return Failed(error: error)
        }
    }
}

private final class Failed: AppConfigAPI, @unchecked Sendable {
    private let error: any Error

    internal init(error: any Error) {
        self.error = error
    }

    func start(params: AppConfigAPIParams?) async -> APIResult<AppConfig, AppConfigFailure> {
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
