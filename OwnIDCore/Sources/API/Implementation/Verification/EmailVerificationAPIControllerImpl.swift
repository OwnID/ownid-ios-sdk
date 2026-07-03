import Foundation

internal final class EmailVerificationAPIControllerImpl: EmailVerificationAPIController {
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

    func completeWithCode(code: String) async -> APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure> {
        do {
            let request = try EmailVerificationCompleteAPICall(
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

    func resend() async -> APIResult<Void, EmailVerificationResendAPIFailure> {
        do {
            let request = try EmailVerificationResendAPICall(
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

    func cancel(reason: Reason) async -> APIResult<Void, EmailVerificationCancelAPIFailure> {
        do {
            let request = try EmailVerificationCancelAPICall(
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
