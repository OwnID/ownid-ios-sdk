import Foundation

internal final class PasskeyAssertionAPIControllerImpl: PasskeyAssertionAPIController {
    let assertionOptions: AssertionOptions
    let accessToken: AccessToken?
    private let traceParent: String?

    private let apiBaseURL: URL
    private let network: any NetworkProtocol
    private let coder: any JSONCoder
    private let interceptor: (any APICallInterceptor)?

    internal init(
        apiBaseURL: URL,
        network: any NetworkProtocol,
        coder: any JSONCoder,
        assertionOptions: AssertionOptions,
        accessToken: AccessToken?,
        traceParent: String?,
        interceptor: (any APICallInterceptor)?
    ) {
        self.apiBaseURL = apiBaseURL
        self.network = network
        self.coder = coder
        self.assertionOptions = assertionOptions
        self.accessToken = accessToken
        self.traceParent = traceParent
        self.interceptor = interceptor
    }

    func verify(assertionResult: AssertionResult) async -> APIResult<AccessToken, PasskeyAssertionVerifyAPIFailure> {
        do {
            let request = try PasskeyAssertionResultAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                assertionResult: assertionResult,
                accessToken: accessToken,
                traceParent: traceParent,
            )
            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }

    func cancel(reason: Reason) async -> APIResult<Void, PasskeyAssertionCancelAPIFailure> {
        do {
            let request = try PasskeyAssertionCancelAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                challenge: assertionOptions.challenge,
                reason: reason,
                traceParent: traceParent
            )
            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }
}
