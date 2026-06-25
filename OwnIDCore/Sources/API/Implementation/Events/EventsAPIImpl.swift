import Foundation

internal final class EventsAPIImpl: EventsAPI {
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

    internal func start(params: EventsAPIParams) async -> APIResult<Void, EventsFailure> {
        do {
            let traceParent = params.traceParent ?? TraceContext.generateTraceParent()
            let request = try EventsAPICall(
                apiBaseURL: try apiBaseURL.getBaseURL(),
                coder: coder,
                userJourney: params.userJourney,
                traceParent: traceParent
            )
            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }

    internal static func create(resolver: any DIContainerResolver) -> any EventsAPI {
        do {
            return EventsAPIImpl(
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

private final class Failed: EventsAPI, @unchecked Sendable {
    private let error: any Error

    internal init(error: any Error) {
        self.error = error
    }

    func start(params: EventsAPIParams) async -> APIResult<Void, EventsFailure> {
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
