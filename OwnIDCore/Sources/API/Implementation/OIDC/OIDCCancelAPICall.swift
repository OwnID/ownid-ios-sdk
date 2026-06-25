import Foundation

internal final class OIDCCancelAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        challengeID: ChallengeID,
        reason: Reason,
        accessToken: AccessToken?,
        traceParent: String?,
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("oidc/idp/cancel"))

        let reason: InternalCancelReason =
            switch reason {
            case .timeout: InternalCancelReason.timeout
            case .userClose: InternalCancelReason.userClose
            case .moveToOtherChallenge: InternalCancelReason.moveToOtherChallenge
            case .systemError: InternalCancelReason.systemError
            case .unknown: InternalCancelReason.unknown
            case .alreadyExists: InternalCancelReason.alreadyExists
            }

        let requestBody = InternalCancelOidcChallengeRequest(challengeId: InternalChallengeId(challengeID.value), reason: reason)

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<Void, OIDCCancelAPIFailure> {
        guard successResponse.code == 204 else { return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail())) }
        return .success(())
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> OIDCCancelAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadChallengeRequestErrorResponse.self,
                unexpected: OIDCCancelAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
                    invalidChallenge: { .badRequest(.invalidChallenge(errorCode: $0, message: $1, challengeID: $2)) },
                    maximumAttemptsReached: { .badRequest(.maximumAttemptsReached(errorCode: $0, message: $1, challengeID: $2)) },
                    unknown: { .badRequest(.unknown(errorCode: $0, message: $1)) }
                )
            }

        case 403:
            do {
                let response = try coder.decodeFromString(failResponse.body, as: InternalForbiddenErrorResponse.self)
                guard response.errorCode == .forbidden else {
                    throw internalUnexpectedErrorCode(response.errorCode, for: "forbidden response", codingPath: [])
                }
                return .forbidden(errorCode: response.errorCode.toDomainModel(), message: response.message)
            } catch {
                return failResponse.toForbiddenErrorFailure(
                    { .forbidden(errorCode: $0, message: $1) },
                    unexpected: { .unexpected(errorCode: $0, message: $1, underlyingError: $2) },
                    error: error
                )
            }

        default:
            return failResponse.toUnexpectedFailure(OIDCCancelAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> OIDCCancelAPIFailure {
        failResponse.toUnexpectedFailure(OIDCCancelAPIFailure.unexpected)
    }
}
