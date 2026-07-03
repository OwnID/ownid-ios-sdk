import Foundation

internal final class PhoneVerificationCancelAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        challengeID: ChallengeID,
        accessToken: AccessToken?,
        reason: Reason,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("verifications/phone/cancel"))

        let reason: InternalCancelReason =
            switch reason {
            case .timeout: InternalCancelReason.timeout
            case .userClose: InternalCancelReason.userClose
            case .moveToOtherChallenge: InternalCancelReason.moveToOtherChallenge
            case .systemError: InternalCancelReason.systemError
            case .unknown: InternalCancelReason.unknown
            case .alreadyExists: InternalCancelReason.alreadyExists
            }

        let requestBody = InternalCancelVerificationRequest(challengeId: InternalChallengeId(challengeID.value), reason: reason)

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<Void, PhoneVerificationCancelAPIFailure> {
        guard successResponse.code == 204 else { return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail())) }
        return .success(())
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PhoneVerificationCancelAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadChallengeRequestErrorResponse.self,
                unexpected: PhoneVerificationCancelAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
                    invalidChallenge: { .badRequest(.invalidChallenge(errorCode: $0, message: $1, challengeID: $2)) },
                    maximumAttemptsReached: { .badRequest(.maximumAttemptsReached(errorCode: $0, message: $1, challengeID: $2)) },
                    unknown: { .badRequest(.unknown(errorCode: $0, message: $1)) }
                )
            }

        default:
            return failResponse.toUnexpectedFailure(PhoneVerificationCancelAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PhoneVerificationCancelAPIFailure {
        failResponse.toUnexpectedFailure(PhoneVerificationCancelAPIFailure.unexpected)
    }
}
