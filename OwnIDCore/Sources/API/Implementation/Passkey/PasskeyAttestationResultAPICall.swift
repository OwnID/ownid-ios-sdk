import Foundation

internal final class PasskeyAttestationResultAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        attestationResult: AttestationResult,
        accessToken: AccessToken?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("passkeys/attestation/result"))

        let type: InternalCredentialType =
            switch attestationResult.type {
            case .publicKey: InternalCredentialType.publicKey
            }

        let transports = attestationResult.response.transports.map { type in
            switch type {
            case .usb: return InternalTransportType.usb
            case .nfc: return InternalTransportType.nfc
            case .ble: return InternalTransportType.ble
            case .smartCard: return InternalTransportType.smartCard
            case .hybrid: return InternalTransportType.hybrid
            case .internal: return InternalTransportType.internal
            case .cable: return InternalTransportType.cable
            }
        }

        let response = InternalAttestationAuthenticatorResponse(
            clientDataJSON: attestationResult.response.clientDataJSON,
            attestationObject: attestationResult.response.attestationObject,
            transports: transports
        )

        let authenticatorAttachment: InternalAuthenticatorAttachment? = attestationResult.authenticatorAttachment.map { attachment in
            switch attachment {
            case .platform: return InternalAuthenticatorAttachment.platform
            case .crossPlatform: return InternalAuthenticatorAttachment.crossPlatform
            }
        }

        let requestBody = InternalAttestationResultRequest(
            id: attestationResult.id,
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

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<AttestationResponse, PasskeyAttestationVerifyAPIFailure> {
        guard successResponse.code == 200 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let parsed = try coder.decodeFromString(successResponse.body, as: InternalAttestationResultResponse.self)
            let response = InternalAttestationResultResponse(
                ownIdData: try RawJSONObjectFieldExtractor.extractRequiredTopLevelRawValue(
                    from: successResponse.body,
                    fieldName: "ownIdData"
                ),
                proofToken: parsed.proofToken
            )

            return .success(
                AttestationResponse(
                    proofToken: ProofToken(token: response.proofToken),
                    ownIdData: response.ownIdData
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

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PasskeyAttestationVerifyAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadChallengeRequestErrorResponse.self,
                unexpected: PasskeyAttestationVerifyAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    invalidArgument: { .badRequest(.invalidArgument(errorCode: $0, message: $1)) },
                    invalidChallenge: { .badRequest(.invalidChallenge(errorCode: $0, message: $1, challengeID: $2)) },
                    maximumAttemptsReached: { .badRequest(.maximumAttemptsReached(errorCode: $0, message: $1, challengeID: $2)) },
                    unknown: { .badRequest(.unknown(errorCode: $0, message: $1)) }
                )
            }

        case 401:
            if failResponse.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .unauthorized(errorCode: .unauthorized, message: String(describing: NetworkResponse.Fail.httpError(failResponse)))
            }
            do {
                let response = try coder.decodeFromString(failResponse.body, as: InternalUnauthorizedErrorResponse.self)
                guard response.errorCode == .unauthorized else {
                    throw internalUnexpectedErrorCode(response.errorCode, for: "unauthorized response", codingPath: [])
                }
                return .unauthorized(errorCode: response.errorCode.toDomainModel(), message: response.message)
            } catch {
                return failResponse.toUnexpectedFailure(PasskeyAttestationVerifyAPIFailure.unexpected, error: error)
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
                return failResponse.toUnexpectedFailure(PasskeyAttestationVerifyAPIFailure.unexpected, error: error)
            }

        default:
            return failResponse.toUnexpectedFailure(PasskeyAttestationVerifyAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PasskeyAttestationVerifyAPIFailure {
        failResponse.toUnexpectedFailure(PasskeyAttestationVerifyAPIFailure.unexpected)
    }
}
