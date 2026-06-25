import Foundation

internal final class PhoneVerificationAPIControllerImpl: PhoneVerificationAPIController {
    let challenge: VerificationChallenge
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
        challenge: VerificationChallenge,
        accessToken: AccessToken?,
        traceParent: String?,
        interceptor: (any APICallInterceptor)?
    ) {
        self.apiBaseURL = apiBaseURL
        self.network = network
        self.coder = coder
        self.challenge = challenge
        self.accessToken = accessToken
        self.traceParent = traceParent
        self.interceptor = interceptor
    }

    func completeWithCode(code: String) async -> APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure> {
        do {
            let request = try PhoneVerificationCompleteAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                challengeID: challenge.challengeID,
                code: code,
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

    func resend() async -> APIResult<Void, PhoneVerificationResendAPIFailure> {
        do {
            let request = try PhoneVerificationResendAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                challengeID: challenge.challengeID,
                accessToken: accessToken,
                traceParent: traceParent
            )
            return try await request.executeWithInterceptor(network: network, interceptor: interceptor)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failure(error.toAPIUnexpectedFailure { .unexpected(errorCode: $0, message: $1, underlyingError: $2) })
        }
    }

    func cancel(reason: Reason) async -> APIResult<Void, PhoneVerificationCancelAPIFailure> {
        do {
            let request = try PhoneVerificationCancelAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                challengeID: challenge.challengeID,
                accessToken: accessToken,
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
