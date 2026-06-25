import Foundation

internal final class PasskeyAssertionOptionsAPICall: APICall {
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

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("passkeys/assertion/options"))

        if let loginID {
            let requestBody = InternalAssertionOptionsRequest(
                loginId: InternalLoginId(id: loginID.id, type: loginID.type.toInternalModel())
            )
            request.setBody(try coder.encodeToString(requestBody))
        }

        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<AssertionOptions, PasskeyAssertionStartAPIFailure> {
        guard successResponse.code == 201 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let response = try coder.decodeFromString(successResponse.body, as: InternalAssertionOptionsResponse.self)
            try WebAuthnOptionsValidation.validateAssertionOptionsResponse(response)
            let assertionOptions = AssertionOptions(
                challenge: ChallengeID(response.challenge.value),
                rpID: response.rpId,
                allowCredentials: response.allowCredentials?.map(Self.mapCredentialDescriptor(_:)),
                userVerification: response.userVerification.map(Self.mapUserVerification(_:)),
                timeout: response.timeout.map { Timeout(milliseconds: $0.value) }
            )
            return .success(assertionOptions)
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PasskeyAssertionStartAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadLoginIdRequestErrorResponse.self,
                unexpected: PasskeyAssertionStartAPIFailure.unexpected
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

        case 404:
            do {
                let response = try coder.decodeFromString(failResponse.body, as: InternalUserNotFoundErrorResponse.self)
                guard response.errorCode == .userNotFound else {
                    throw internalUnexpectedErrorCode(response.errorCode, for: "user_not_found response", codingPath: [])
                }
                return .userNotFound(errorCode: response.errorCode.toDomainModel(), message: response.message)
            } catch {
                return failResponse.toUnexpectedFailure(PasskeyAssertionStartAPIFailure.unexpected, error: error)
            }

        case 424:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalFailedDependencyErrorResponse.self,
                unexpected: PasskeyAssertionStartAPIFailure.unexpected
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
                return failResponse.toUnexpectedFailure(PasskeyAssertionStartAPIFailure.unexpected, error: error)
            }

        default:
            return failResponse.toUnexpectedFailure(PasskeyAssertionStartAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PasskeyAssertionStartAPIFailure {
        failResponse.toUnexpectedFailure(PasskeyAssertionStartAPIFailure.unexpected)
    }

    private static func mapCredentialDescriptor(_ descriptor: InternalPublicKeyCredentialDescriptor) -> PublicKeyCredentialDescriptor {
        PublicKeyCredentialDescriptor(
            id: descriptor.id,
            type: mapCredentialType(descriptor.type),
            transports: descriptor.transports?.map(Self.mapTransport(_:))
        )
    }

    private static func mapCredentialType(_ type: InternalCredentialType) -> CredentialType {
        switch type {
        case .publicKey: return .publicKey
        }
    }

    private static func mapTransport(_ transport: InternalTransportType) -> TransportType {
        switch transport {
        case .usb: return .usb
        case .nfc: return .nfc
        case .ble: return .ble
        case .smartCard: return .smartCard
        case .hybrid: return .hybrid
        case .internal: return .internal
        case .cable: return .cable
        }
    }

    private static func mapUserVerification(_ verification: InternalUserVerification) -> UserVerification {
        switch verification {
        case .required: return .required
        case .preferred: return .preferred
        case .discouraged: return .discouraged
        }
    }
}
