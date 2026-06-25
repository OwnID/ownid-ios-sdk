import Foundation

internal final class OIDCAPIControllerImpl: OIDCAPIController {
    let challenge: SocialChallenge
    let accessToken: AccessToken?
    private let traceParent: String?
    private let expectedResponseType: OAuthResponseType

    private let apiBaseURL: URL
    private let coder: any JSONCoder
    private let network: any NetworkProtocol
    private let interceptor: (any APICallInterceptor)?

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        network: any NetworkProtocol,
        challenge: SocialChallenge,
        accessToken: AccessToken?,
        traceParent: String?,
        expectedResponseType: OAuthResponseType,
        interceptor: (any APICallInterceptor)?
    ) {
        self.coder = coder
        self.apiBaseURL = apiBaseURL
        self.network = network
        self.challenge = challenge
        self.accessToken = accessToken
        self.traceParent = traceParent
        self.expectedResponseType = expectedResponseType
        self.interceptor = interceptor
    }

    func completeWithToken(idToken: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> {
        guard expectedResponseType == .idToken else {
            return .failure(
                .badRequest(
                    .invalidArgument(
                        errorCode: .invalidArgument,
                        message:
                            "OIDC completion method does not match requested response type. Expected: \(expectedResponseType), actual: \(OAuthResponseType.idToken)"
                    )
                )
            )
        }
        do {
            let request = try OIDCCompleteIDTokenAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                challengeID: challenge.challengeID,
                idToken: idToken,
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

    func completeWithCode(code: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> {
        guard expectedResponseType == .code else {
            return .failure(
                .badRequest(
                    .invalidArgument(
                        errorCode: .invalidArgument,
                        message:
                            "OIDC completion method does not match requested response type. Expected: \(expectedResponseType), actual: \(OAuthResponseType.code)"
                    )
                )
            )
        }
        do {
            let request = try OIDCCompleteCodeAPICall(
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

    func cancel(reason: Reason) async -> APIResult<Void, OIDCCancelAPIFailure> {
        do {
            let request = try OIDCCancelAPICall(
                apiBaseURL: apiBaseURL,
                coder: coder,
                challengeID: challenge.challengeID,
                reason: reason,
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
}
