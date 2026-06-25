import Foundation

/// Bad request.
///
/// OpenAPI source: `BadLoginIdRequestErrorResponse` response.
internal enum InternalBadLoginIdRequestErrorResponse: Sendable, Decodable {
    case invalidArgument(InternalInvalidArgumentErrorResponse)
    case loginIDValidation(InternalLoginIdValidationErrorResponse)
    case loginIDTypeNotSupported(InternalLoginIdTypeNotSupportedErrorResponse)
    case unknown(InternalUnknownErrorResponse)

    internal init(from decoder: Decoder) throws {
        let discriminator = try InternalErrorResponseDiscriminator(from: decoder)
        switch discriminator.errorCode {
        case .invalidArgument:
            self = .invalidArgument(try InternalInvalidArgumentErrorResponse(from: decoder))
        case .loginIdValidationFailed:
            self = .loginIDValidation(try InternalLoginIdValidationErrorResponse(from: decoder))
        case .loginIDTypeNotSupported:
            self = .loginIDTypeNotSupported(try InternalLoginIdTypeNotSupportedErrorResponse(from: decoder))
        case .unknown:
            self = .unknown(try InternalUnknownErrorResponse(from: decoder))
        default:
            throw internalUnexpectedErrorCode(
                discriminator.errorCode,
                for: "InternalBadLoginIdRequestErrorResponse",
                codingPath: decoder.codingPath
            )
        }
    }

    internal func toFailure<T>(
        invalidArgument: (ErrorCode, String) -> T,
        loginIDValidation: (ErrorCode, String, LoginID, String) -> T,
        loginIDTypeNotSupported: (ErrorCode, String) -> T,
        unknown: (ErrorCode, String) -> T
    ) -> T {
        switch self {
        case .invalidArgument(let response):
            return invalidArgument(response.errorCode.toDomainModel(), response.message)
        case .loginIDValidation(let response):
            return loginIDValidation(response.errorCode.toDomainModel(), response.message, response.loginId.toDomainModel(), response.regex)
        case .loginIDTypeNotSupported(let response):
            return loginIDTypeNotSupported(response.errorCode.toDomainModel(), response.message)
        case .unknown(let response):
            return unknown(response.errorCode.toDomainModel(), response.message)
        }
    }
}
