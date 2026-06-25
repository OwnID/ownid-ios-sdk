import Foundation

internal final class PhoneVerificationStartAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        loginID: LoginID?,
        loginIDHintID: String?,
        accessToken: AccessToken?,
        verificationMethods: Set<VerificationMethod>?,
        magicLinkRedirectURL: String?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("verifications/phone/start"))

        var internalLoginId: InternalLoginId? = nil
        if let loginID = loginID {
            internalLoginId = InternalLoginId(id: loginID.id, type: loginID.type.toInternalModel())
        }

        let internalVerificationMethods: [InternalVerificationMethod]? = verificationMethods?.map { method in
            InternalVerificationMethod(rawValue: method.rawValue)
        }.compactMap { $0 }

        let requestBody = InternalStartVerificationRequest(
            loginId: internalLoginId,
            loginIDHintID: loginIDHintID,
            verificationMethods: internalVerificationMethods,
            magicLinkRedirectURL: magicLinkRedirectURL
        )

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<VerificationChallenge, PhoneVerificationStartAPIFailure> {
        guard successResponse.code == 201 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let challengeResponse = try coder.decodeFromString(successResponse.body, as: InternalStartVerificationResponse.self)

            let resend = VerificationChallenge.ResendPolicy(
                allow: challengeResponse.resendPolicy.allow,
                attempts: challengeResponse.resendPolicy.attempts,
                debounce: max(challengeResponse.resendPolicy.debounce, 1)
            )

            let methods = VerificationChallenge.Methods(
                otp: challengeResponse.methods.otp.map { VerificationChallenge.Methods.Otp(length: max($0.length ?? 4, 4)) },
                magicLink: challengeResponse.methods.magicLink.map { _ in VerificationChallenge.Methods.MagicLink() }
            )

            return .success(
                VerificationChallenge(
                    challengeID: ChallengeID(challengeResponse.challengeId.value),
                    resendPolicy: resend,
                    timeout: Timeout(milliseconds: challengeResponse.timeout.value),
                    attempts: challengeResponse.attempts,
                    methods: methods,
                    channel: OperationChannel(channel: challengeResponse.channel.channel, id: challengeResponse.channel.id)
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PhoneVerificationStartAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadVerificationRequestErrorResponse.self,
                unexpected: PhoneVerificationStartAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
                    loginIDValidation: { .badRequest(.invalidLoginID(errorCode: $0, message: $1, loginID: $2, regex: $3)) },
                    loginIDTypeNotSupported: { .badRequest(.unsupportedLoginIDType(errorCode: $0, message: $1)) },
                    missingChannel: { .badRequest(.missingChannel(errorCode: $0, message: $1, loginID: $2)) },
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

        case 404:
            do {
                let response = try coder.decodeFromString(failResponse.body, as: InternalUserNotFoundErrorResponse.self)
                guard response.errorCode == .userNotFound else {
                    throw internalUnexpectedErrorCode(response.errorCode, for: "user_not_found response", codingPath: [])
                }
                return .userNotFound(errorCode: response.errorCode.toDomainModel(), message: response.message)
            } catch {
                return failResponse.toUnexpectedFailure(PhoneVerificationStartAPIFailure.unexpected, error: error)
            }

        case 424:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalFailedDependencyErrorResponse.self,
                unexpected: PhoneVerificationStartAPIFailure.unexpected
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
                return failResponse.toUnexpectedFailure(PhoneVerificationStartAPIFailure.unexpected, error: error)
            }

        default:
            return failResponse.toUnexpectedFailure(PhoneVerificationStartAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PhoneVerificationStartAPIFailure {
        failResponse.toUnexpectedFailure(PhoneVerificationStartAPIFailure.unexpected)
    }
}
