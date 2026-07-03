import Foundation

/// Bad verification start request.
///
/// OpenAPI source: `BadVerificationRequestErrorResponse` response.
internal enum InternalBadVerificationRequestErrorResponse: Sendable, Decodable {
    case invalidArgument(InternalInvalidArgumentErrorResponse)
    case loginIDValidation(InternalLoginIdValidationErrorResponse)
    case loginIDTypeNotSupported(InternalLoginIdTypeNotSupportedErrorResponse)
    case missingChannel(InternalMissingChannelErrorResponse)
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
        case .missingChannel:
            self = .missingChannel(try InternalMissingChannelErrorResponse(from: decoder))
        case .unknown:
            self = .unknown(try InternalUnknownErrorResponse(from: decoder))
        default:
            throw internalUnexpectedErrorCode(
                discriminator.errorCode,
                for: "InternalBadVerificationRequestErrorResponse",
                codingPath: decoder.codingPath
            )
        }
    }

    internal func toFailure<T>(
        invalidArgument: (ErrorCode, String) -> T,
        loginIDValidation: (ErrorCode, String, LoginID, String) -> T,
        loginIDTypeNotSupported: (ErrorCode, String) -> T,
        missingChannel: (ErrorCode, String, LoginID) -> T,
        unknown: (ErrorCode, String) -> T
    ) -> T {
        switch self {
        case .invalidArgument(let response):
            return invalidArgument(response.errorCode.toDomainModel(), response.message)
        case .loginIDValidation(let response):
            return loginIDValidation(response.errorCode.toDomainModel(), response.message, response.loginId.toDomainModel(), response.regex)
        case .loginIDTypeNotSupported(let response):
            return loginIDTypeNotSupported(response.errorCode.toDomainModel(), response.message)
        case .missingChannel(let response):
            return missingChannel(response.errorCode.toDomainModel(), response.message, response.loginId.toDomainModel())
        case .unknown(let response):
            return unknown(response.errorCode.toDomainModel(), response.message)
        }
    }
}
