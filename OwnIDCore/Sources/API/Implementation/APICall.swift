import Foundation

/// Internal adapter between one Auth Server endpoint and the SDK's typed ``APIResult`` contract.
///
/// Implementations own the endpoint boundary: they translate network outcomes into the endpoint's public success and
/// failure types. ``execute(network:request:)`` performs one network dispatch for the supplied ``request``; it does not
/// retry, persist state, or emit telemetry on its own. Cancellation is thrown from this layer and converted to
/// ``APIResult/canceled`` by public API wrappers.
internal protocol APICall {
    associatedtype APISuccess: Sendable
    associatedtype APIFailure: Sendable

    var request: NetworkRequest { get }

    func execute(network: any NetworkProtocol, request: NetworkRequest) async throws -> APIResult<APISuccess, APIFailure>

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<APISuccess, APIFailure>

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> APIFailure

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> APIFailure
}

extension APICall {
    /// Runs the request and dispatches the network result to the endpoint boundary.
    ///
    /// `CancellationError` and `URLError.cancelled` are rethrown so the public API wrapper can return
    /// ``APIResult/canceled``. Other thrown errors are left for the wrapper to convert into an unexpected failure.
    internal func execute(network: any NetworkProtocol, request: NetworkRequest) async throws -> APIResult<APISuccess, APIFailure> {
        do {
            switch try await network.run(request) {
            case .success(let successResponse):
                return mapHttpSuccess(successResponse)

            case .fail(.httpError(let failResponse)):
                return .failure(mapHttpError(failResponse))

            case .fail(let failResponse):
                return .failure(mapUnhandled(failResponse))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        }
    }

    internal func execute(network: any NetworkProtocol) async throws -> APIResult<APISuccess, APIFailure> {
        try await execute(network: network, request: request)
    }
}
