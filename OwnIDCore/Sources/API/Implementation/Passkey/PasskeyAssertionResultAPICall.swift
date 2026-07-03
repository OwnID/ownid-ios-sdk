import Foundation

internal final class PasskeyAssertionResultAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        assertionResult: AssertionResult,
        accessToken: AccessToken?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("passkeys/assertion/result"))

        let type: InternalCredentialType =
            switch assertionResult.type {
            case .publicKey: InternalCredentialType.publicKey
            }

        let response = InternalAssertionAuthenticatorResponse(
            clientDataJSON: assertionResult.response.clientDataJSON,
            authenticatorData: assertionResult.response.authenticatorData,
            userHandle: assertionResult.response.userHandle,
            signature: assertionResult.response.signature
        )

        let attachment = assertionResult.authenticatorAttachment ?? .platform
        let authenticatorAttachment: InternalAuthenticatorAttachment =
            switch attachment {
            case .platform: InternalAuthenticatorAttachment.platform
            case .crossPlatform: InternalAuthenticatorAttachment.crossPlatform
            }

        let requestBody = InternalAssertionResultRequest(
            id: assertionResult.id,
            type: type,
            response: response,
            authenticatorAttachment: authenticatorAttachment
        )

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<AccessToken, PasskeyAssertionVerifyAPIFailure> {
        guard successResponse.code == 200 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let token = try coder.decodeFromString(successResponse.body, as: InternalAssertionResultResponse.self)
            return .success(AccessToken(token: token.accessToken))
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PasskeyAssertionVerifyAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadChallengeRequestErrorResponse.self,
                unexpected: PasskeyAssertionVerifyAPIFailure.unexpected
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
            return failResponse.toUnexpectedFailure(PasskeyAssertionVerifyAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PasskeyAssertionVerifyAPIFailure {
        failResponse.toUnexpectedFailure(PasskeyAssertionVerifyAPIFailure.unexpected)
    }
}
