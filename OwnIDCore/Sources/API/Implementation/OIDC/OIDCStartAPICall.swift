import Foundation

internal final class OIDCStartAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        provider: SocialProviderID,
        oauthResponseType: OAuthResponseType,
        accessToken: AccessToken?,
        loginIDHint: String? = nil,
        redirectURI: String? = nil,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(
            url: apiBaseURL.appendingPathComponent("oidc/idp/start").appendingPathComponent(provider.rawValue.lowercased())
        )

        let type: InternalStartOidcChallengeRequestOauthResponseType =
            switch oauthResponseType {
            case .code: InternalStartOidcChallengeRequestOauthResponseType.code
            case .idToken: InternalStartOidcChallengeRequestOauthResponseType.idToken
            }

        let requestBody = InternalStartOidcChallengeRequest(
            loginIdHint: loginIDHint,
            oauthResponseType: type,
            redirectUri: redirectURI
        )

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<SocialChallenge, OIDCStartAPIFailure> {
        guard successResponse.code == 201 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let internalChallenge = try coder.decodeFromString(successResponse.body, as: InternalOidcChallengeResponse.self)
            let challenge = SocialChallenge(
                challengeID: ChallengeID(internalChallenge.challengeId.value),
                timeout: Timeout(milliseconds: internalChallenge.timeout.value),
                clientID: internalChallenge.clientId,
                challengeURL: internalChallenge.challengeUrl
            )
            return .success(challenge)
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> OIDCStartAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadRequestErrorResponse.self,
                unexpected: OIDCStartAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
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
                unexpected: OIDCStartAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    provider: { .failedDependency(.providerFailed(errorCode: $0, message: $1, scope: $2)) },
                    missingProvider: { .failedDependency(.missingProvider(errorCode: $0, message: $1, capability: $2, scope: $3)) }
                )
            }

        case 429:
            do {
                let response = try coder.decodeFromString(failResponse.body, as: InternalMaximumChallengesReachedErrorResponse.self)
                guard response.errorCode == .maximumChallengesReached else {
                    throw internalUnexpectedErrorCode(response.errorCode, for: "maximum_challenges_reached response", codingPath: [])
                }
                return .maximumChallengesReached(errorCode: response.errorCode.toDomainModel(), message: response.message)
            } catch {
                return failResponse.toUnexpectedFailure(OIDCStartAPIFailure.unexpected, error: error)
            }

        default:
            return failResponse.toUnexpectedFailure(OIDCStartAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> OIDCStartAPIFailure {
        failResponse.toUnexpectedFailure(OIDCStartAPIFailure.unexpected)
    }
}
