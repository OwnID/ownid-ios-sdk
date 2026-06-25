import Foundation

internal final class PasskeyAttestationAPIControllerImpl: PasskeyAttestationAPIController {
    let attestationOptions: AttestationOptions
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
        attestationOptions: AttestationOptions,
        accessToken: AccessToken?,
        traceParent: String?,
        interceptor: (any APICallInterceptor)?
    ) {
        self.apiBaseURL = apiBaseURL
        self.network = network
        self.coder = coder
        self.attestationOptions = attestationOptions
        self.accessToken = accessToken
        self.traceParent = traceParent
        self.interceptor = interceptor
    }

    func verify(attestationResult: AttestationResult) async -> APIResult<AttestationResponse, PasskeyAttestationVerifyAPIFailure> {
        do {
            let request = try PasskeyAttestationResultAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                attestationResult: attestationResult,
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

    func cancel(reason: Reason) async -> APIResult<Void, PasskeyAttestationCancelAPIFailure> {
        do {
            let request = try PasskeyAttestationCancelAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                challenge: attestationOptions.challenge,
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
