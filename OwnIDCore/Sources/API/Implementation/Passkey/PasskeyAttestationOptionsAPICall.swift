import Foundation

internal final class PasskeyAttestationOptionsAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        loginID: LoginID?,
        accountDisplayName: String?,
        accessToken: AccessToken?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("passkeys/attestation/options"))

        let internalLoginId: InternalLoginId? = loginID.map { loginID in
            InternalLoginId(id: loginID.id, type: loginID.type.toInternalModel())
        }

        if internalLoginId != nil || accountDisplayName != nil {
            let requestBody = InternalAttestationOptionsRequest(
                loginId: internalLoginId,
                accountDisplayName: accountDisplayName
            )

            let body = try coder.encodeToString(requestBody)
            request.setBody(body)
        }

        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<AttestationOptions, PasskeyAttestationStartAPIFailure> {
        guard successResponse.code == 200 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let response = try coder.decodeFromString(successResponse.body, as: InternalAttestationOptionsResponse.self)
            try WebAuthnOptionsValidation.validateAttestationOptionsResponse(response)
            let pubKeyCredParams = response.pubKeyCredParams.map(Self.mapPubKeyCredParams(_:))
            let attestationOptions = AttestationOptions(
                rp: AttestationOptions.RelayingParty(id: response.rp.id, name: response.rp.name),
                user: AttestationOptions.User(id: response.user.id, name: response.user.name, displayName: response.user.displayName),
                challenge: ChallengeID(response.challenge.value),
                pubKeyCredParams: pubKeyCredParams.isEmpty
                    ? [.init(type: .publicKey, alg: .ES256), .init(type: .publicKey, alg: .RS256)]
                    : pubKeyCredParams,
                attestation: response.attestation.map(Self.mapAttestation(_:)),
                authenticatorSelection: response.authenticatorSelection.map(Self.mapAuthenticatorSelection(_:)),
                timeout: response.timeout.map { Timeout(milliseconds: $0.value) },
                excludeCredentials: response.excludeCredentials?.map(Self.mapCredentialDescriptor(_:))
            )
            return .success(attestationOptions)
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PasskeyAttestationStartAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadLoginIdRequestErrorResponse.self,
                unexpected: PasskeyAttestationStartAPIFailure.unexpected
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
                unexpected: PasskeyAttestationStartAPIFailure.unexpected
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
                return failResponse.toUnexpectedFailure(PasskeyAttestationStartAPIFailure.unexpected, error: error)
            }

        default:
            return failResponse.toUnexpectedFailure(PasskeyAttestationStartAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PasskeyAttestationStartAPIFailure {
        failResponse.toUnexpectedFailure(PasskeyAttestationStartAPIFailure.unexpected)
    }

    private static func mapPubKeyCredParams(
        _ params: InternalAttestationOptionsResponsePubKeyCredParamsItem
    ) -> AttestationOptions.PubKeyCredParams {
        let type: CredentialType
        switch params.type {
        case .publicKey: type = .publicKey
        }
        let algorithm: KeyAlgorithmType
        switch params.alg {
        case .number7: algorithm = .ES256
        case .number257: algorithm = .RS256
        }
        return AttestationOptions.PubKeyCredParams(type: type, alg: algorithm)
    }

    private static func mapAttestation(_ value: InternalAttestationConveyancePreference) -> AttestationConveyancePreference {
        switch value {
        case .none: return .none
        case .direct: return .direct
        case .indirect: return .indirect
        case .enterprise: return .enterprise
        }
    }

    private static func mapAuthenticatorSelection(
        _ selection: InternalAttestationOptionsResponseAuthenticatorSelection
    ) -> AttestationOptions.AuthenticatorSelection {
        AttestationOptions.AuthenticatorSelection(
            authenticatorAttachment: selection.authenticatorAttachment.map(Self.mapAuthenticatorAttachment(_:)),
            userVerification: selection.userVerification.map(Self.mapUserVerification(_:)),
            residentKey: selection.residentKey.map(Self.mapResidentKey(_:))
        )
    }

    private static func mapAuthenticatorAttachment(_ value: InternalAuthenticatorAttachment) -> AuthenticatorAttachment {
        switch value {
        case .platform: return .platform
        case .crossPlatform: return .crossPlatform
        }
    }

    private static func mapUserVerification(_ value: InternalUserVerification) -> UserVerification {
        switch value {
        case .required: return .required
        case .preferred: return .preferred
        case .discouraged: return .discouraged
        }
    }

    private static func mapResidentKey(_ value: InternalResidentKey) -> ResidentKey {
        switch value {
        case .required: return .required
        case .preferred: return .preferred
        case .discouraged: return .discouraged
        }
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
}
