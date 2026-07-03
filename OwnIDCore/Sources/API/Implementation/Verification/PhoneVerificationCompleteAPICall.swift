import Foundation

internal final class PhoneVerificationCompleteAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        challengeID: ChallengeID,
        code: String,
        accessToken: AccessToken?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("verifications/phone/complete"))

        let requestBody = InternalCompleteVerificationRequest(challengeId: InternalChallengeId(challengeID.value), code: code)

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure> {
        guard successResponse.code == 200 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let response = try coder.decodeFromString(successResponse.body, as: InternalAccessOrProofTokensResponse.self)

            if let accessToken = response.accessToken {
                return .success(.accessToken(AccessToken(token: accessToken)))
            }

            if let proofToken = response.proofToken {
                return .success(.proofToken(ProofToken(token: proofToken)))
            }

            let message = "Malformed verification complete response"
            return .failure(mapUnhandled(successResponse.toSuccessMappingFail(message: message)))
        } catch {
            return .failure(
                mapUnhandled(
                    successResponse.toSuccessMappingFail(
                        message: "Failed to parse success response from \(successResponse.url)",
                        cause: error
                    )
                )
            )
        }
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PhoneVerificationCompleteAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadCompleteVerificationRequestErrorResponse.self,
                unexpected: PhoneVerificationCompleteAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
                    invalidChallenge: { .badRequest(.invalidChallenge(errorCode: $0, message: $1, challengeID: $2)) },
                    maximumAttemptsReached: {
                        .badRequest(.maximumAttemptsReached(errorCode: $0, message: $1, challengeID: $2))
                    },
                    verificationCodeWrong: {
                        .badRequest(.wrongCode(errorCode: $0, message: $1, challengeID: $2))
                    },
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
            return failResponse.toUnexpectedFailure(PhoneVerificationCompleteAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PhoneVerificationCompleteAPIFailure {
        failResponse.toUnexpectedFailure(PhoneVerificationCompleteAPIFailure.unexpected)
    }
}
