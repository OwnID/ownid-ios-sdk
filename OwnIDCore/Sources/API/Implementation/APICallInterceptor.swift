import Foundation

/// Internal API call interceptor used to decorate requests and observe mapped API results.
///
/// Interceptors are SDK-internal boundaries. They must preserve each endpoint's public success/failure contract unless
/// they intentionally replace the result with another value of the same ``APIResult`` type. Interceptors may add
/// cross-cutting request metadata or telemetry, but they must not make endpoint-specific business decisions.
internal protocol APICallInterceptor: Sendable {
    /// Called before the request is sent to the network layer. Return the request to dispatch.
    func interceptRequest(_ request: NetworkRequest) async -> NetworkRequest

    /// Called after the API call maps network output into ``APIResult``. Return the result visible to the API caller.
    func onResponse<APISuccess: Sendable, APIFailure: Sendable>(
        request: NetworkRequest,
        response: APIResult<APISuccess, APIFailure>
    ) async -> APIResult<APISuccess, APIFailure>
}

extension APICallInterceptor {
    internal func interceptRequest(_ request: NetworkRequest) async -> NetworkRequest {
        request
    }

    internal func onResponse<APISuccess: Sendable, APIFailure: Sendable>(
        request: NetworkRequest,
        response: APIResult<APISuccess, APIFailure>
    ) async -> APIResult<APISuccess, APIFailure> {
        response
    }
}

/// Applies request interceptors in registration order and response interceptors in reverse order.
internal final class APICallPipelineInterceptor: APICallInterceptor {
    private let interceptors: [any APICallInterceptor]

    internal init(interceptors: [any APICallInterceptor]) {
        self.interceptors = interceptors
    }

    internal func interceptRequest(_ request: NetworkRequest) async -> NetworkRequest {
        var interceptedRequest = request
        for interceptor in interceptors {
            interceptedRequest = await interceptor.interceptRequest(interceptedRequest)
        }
        return interceptedRequest
    }

    internal func onResponse<APISuccess: Sendable, APIFailure: Sendable>(
        request: NetworkRequest,
        response: APIResult<APISuccess, APIFailure>
    ) async -> APIResult<APISuccess, APIFailure> {
        var interceptedResponse = response
        for interceptor in interceptors.reversed() {
            interceptedResponse = await interceptor.onResponse(request: request, response: interceptedResponse)
        }
        return interceptedResponse
    }
}

extension APICall {
    /// Executes this API call through an optional ``APICallInterceptor`` while preserving the endpoint's typed result contract.
    internal func executeWithInterceptor(
        network: any NetworkProtocol,
        interceptor: (any APICallInterceptor)?
    ) async throws -> APIResult<APISuccess, APIFailure> {
        let interceptedRequest: NetworkRequest
        if let interceptor {
            interceptedRequest = await interceptor.interceptRequest(request)
        } else {
            interceptedRequest = request
        }

        let response = try await execute(network: network, request: interceptedRequest)
        if let interceptor {
            return await interceptor.onResponse(request: interceptedRequest, response: response)
        }
        return response
    }
}
