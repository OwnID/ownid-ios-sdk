import Foundation

internal final class PhoneEnrollAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        proofToken: ProofToken,
        accessToken: AccessToken?,
        traceParent: String?
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("verifications/phone/enroll"))

        let requestBody = InternalEnrollRequest(proofToken: proofToken.token)

        let body = try coder.encodeToString(requestBody)
        request.setBody(body)
        request.addToRequest(accessToken: accessToken)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<Void, PhoneEnrollAPIFailure> {
        guard successResponse.code == 204 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        return .success(())
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> PhoneEnrollAPIFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadEnrollRequestErrorResponse.self,
                unexpected: PhoneEnrollAPIFailure.unexpected
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

        case 404:
            do {
                let response = try coder.decodeFromString(failResponse.body, as: InternalUserNotFoundErrorResponse.self)
                guard response.errorCode == .userNotFound else {
                    throw internalUnexpectedErrorCode(response.errorCode, for: "user_not_found response", codingPath: [])
                }
                return .userNotFound(errorCode: response.errorCode.toDomainModel(), message: response.message)
            } catch {
                return failResponse.toUnexpectedFailure(PhoneEnrollAPIFailure.unexpected, error: error)
            }

        case 424:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalFailedDependencyErrorResponse.self,
                unexpected: PhoneEnrollAPIFailure.unexpected
            ) { error in
                error.toFailure(
                    provider: { .failedDependency(.providerFailed(errorCode: $0, message: $1, scope: $2)) },
                    missingProvider: { .failedDependency(.missingProvider(errorCode: $0, message: $1, capability: $2, scope: $3)) }
                )
            }

        default:
            return failResponse.toUnexpectedFailure(PhoneEnrollAPIFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> PhoneEnrollAPIFailure {
        failResponse.toUnexpectedFailure(PhoneEnrollAPIFailure.unexpected)
    }
}
