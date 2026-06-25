import Foundation

internal final class OIDCCompleteCodeAPICall: APICall {
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

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("oidc/idp/complete"))

        let requestBody = InternalCompleteOidcChallengeRequest(challengeId: InternalChallengeId(challengeID.value), code: code)

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> {
        guard successResponse.code == 200 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let response = try coder.decodeFromString(successResponse.body, as: InternalAccessTokenWithUserInfoResponse.self)
            return .success(
                AccessTokenWithUserInfo(
                    accessToken: AccessToken(token: response.accessToken),
                    loginID: response.loginId.toDomainModel(),
                    userInfo: response.userInfo,
                    provider: Self.mapProvider(response.provider)
                )
            )
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> OIDCCompleteAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadChallengeRequestErrorResponse.self,
                unexpected: OIDCCompleteAPIFailure.unexpected
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

        case 424:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalFailedDependencyErrorResponse.self,
                unexpected: OIDCCompleteAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    provider: { .failedDependency(.providerFailed(errorCode: $0, message: $1, scope: $2)) },
                    missingProvider: { .failedDependency(.missingProvider(errorCode: $0, message: $1, capability: $2, scope: $3)) }
                )
            }

        default:
            return failResponse.toUnexpectedFailure(OIDCCompleteAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> OIDCCompleteAPIFailure {
        failResponse.toUnexpectedFailure(OIDCCompleteAPIFailure.unexpected)
    }

    private static func mapProvider(_ provider: InternalOidcProvider) -> SocialProviderID {
        switch provider {
        case .apple: return .apple
        case .google: return .google
        }
    }
}
