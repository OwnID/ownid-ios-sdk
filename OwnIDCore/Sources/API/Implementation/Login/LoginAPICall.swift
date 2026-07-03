import Foundation

internal final class LoginAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        loginID: LoginID?,
        accessToken: AccessToken?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("login"))

        let loginIDModel: InternalLoginId?
        if let loginID {
            loginIDModel = InternalLoginId(id: loginID.id, type: loginID.type.toInternalModel())
        } else {
            loginIDModel = nil
        }

        let requestBody = InternalLoginRequest(
            loginId: loginIDModel,
            extendedClientCapabilities: InternalLoginRequestExtendedClientCapabilities(
                passkeys: InternalLoginRequestExtendedClientCapabilitiesPasskeys(peek: true)
            )
        )
        let body = try coder.encodeToString(requestBody)
        request.setBody(body)

        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<LoginResponse, LoginAPIFailure> {
        do {
            switch successResponse.code {
            case 201:
                let parsed = try coder.decodeFromString(successResponse.body, as: InternalLoginResponse.self)
                let response = InternalLoginResponse(
                    accessToken: parsed.accessToken,
                    sessionPayload: try RawJSONObjectFieldExtractor.extractRequiredTopLevelRawValue(
                        from: successResponse.body,
                        fieldName: "sessionPayload"
                    )
                )

                let successData = LoginResponse.Success(
                    accessToken: AccessToken(token: response.accessToken),
                    sessionPayload: response.sessionPayload
                )
                return .success(.success(successData))

            case 206:
                let response = try coder.decodeFromString(successResponse.body, as: InternalAuthRequiredResponse.self)

                if let authRequirements = response.authRequirements {
                    let mappedAuthRequirements = Self.mapAuthRequirements(authRequirements)
                    return .success(
                        .authRequired(LoginResponse.AuthRequired(authRequirements: mappedAuthRequirements, reason: response.reason))
                    )
                }

                if response.accountBlocked != nil {
                    return .success(.accountBlocked(LoginResponse.AccountBlocked(reason: response.reason)))
                }

                if response.accountNotFound != nil {
                    return .success(.accountNotFound(LoginResponse.AccountNotFound(reason: response.reason)))
                }

                return .failure(mapUnhandled(successResponse.toSuccessMappingFail(message: "Malformed 206 login response")))

            default:
                return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
            }
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> LoginAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadLoginIdRequestErrorResponse.self,
                unexpected: LoginAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
                    loginIDValidation: { .badRequest(.invalidLoginID(errorCode: $0, message: $1, loginID: $2, regex: $3)) },
                    loginIDTypeNotSupported: { .badRequest(.unsupportedLoginIDType(errorCode: $0, message: $1)) },
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
                unexpected: LoginAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    provider: { .failedDependency(.providerFailed(errorCode: $0, message: $1, scope: $2)) },
                    missingProvider: { .failedDependency(.missingProvider(errorCode: $0, message: $1, capability: $2, scope: $3)) }
                )
            }

        default:
            return failResponse.toUnexpectedFailure(LoginAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> LoginAPIFailure {
        failResponse.toUnexpectedFailure(LoginAPIFailure.unexpected)
    }

    internal static func mapAuthRequirements(_ authRequirements: InternalAuthRequirements) -> AuthRequirements {
        let operations: [OperationRequirement] = authRequirements.operations.map { internalOperationRequirement in
            let channels: [OperationChannel]? = internalOperationRequirement.channels?.map { channel in
                OperationChannel(channel: channel.channel, id: channel.id)
            }

            return OperationRequirement(
                score: internalOperationRequirement.score,
                type: internalOperationRequirement.type.toDomainModel(),
                channels: channels
            )
        }

        return AuthRequirements(targetScore: authRequirements.targetScore, operations: operations)
    }
}
