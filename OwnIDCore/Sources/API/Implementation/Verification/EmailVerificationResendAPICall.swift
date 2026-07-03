import Foundation

internal final class EmailVerificationResendAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        challengeID: ChallengeID,
        accessToken: AccessToken?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("verifications/email/resend"))

        let requestBody = InternalVerificationRequest(challengeId: InternalChallengeId(challengeID.value))

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<Void, EmailVerificationResendAPIFailure> {
        guard successResponse.code == 204 else { return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail())) }
        return .success(())
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> EmailVerificationResendAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadResendRequestErrorResponse.self,
                unexpected: EmailVerificationResendAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
                    invalidChallenge: { .badRequest(.invalidChallenge(errorCode: $0, message: $1, challengeID: $2)) },
                    maximumResendAttemptsReached: {
                        .badRequest(.maximumResendAttemptsReached(errorCode: $0, message: $1, challengeID: $2))
                    },
                    unknown: { .badRequest(.unknown(errorCode: $0, message: $1)) }
                )
            }

        case 424:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalFailedDependencyErrorResponse.self,
                unexpected: EmailVerificationResendAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    provider: { .failedDependency(.providerFailed(errorCode: $0, message: $1, scope: $2)) },
                    missingProvider: { .failedDependency(.missingProvider(errorCode: $0, message: $1, capability: $2, scope: $3)) }
                )
            }

        default:
            return failResponse.toUnexpectedFailure(EmailVerificationResendAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> EmailVerificationResendAPIFailure {
        failResponse.toUnexpectedFailure(EmailVerificationResendAPIFailure.unexpected)
    }
}
