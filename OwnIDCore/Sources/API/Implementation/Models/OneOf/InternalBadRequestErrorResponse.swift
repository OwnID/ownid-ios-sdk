import Foundation

/// Bad request.
///
/// OpenAPI source: `BadRequestErrorResponse` response.
internal enum InternalBadRequestErrorResponse: Sendable, Decodable {
    case invalidArgument(InternalInvalidArgumentErrorResponse)
    case unknown(InternalUnknownErrorResponse)

    internal init(from decoder: Decoder) throws {
        let discriminator = try InternalErrorResponseDiscriminator(from: decoder)
        switch discriminator.errorCode {
        case .invalidArgument:
            self = .invalidArgument(try InternalInvalidArgumentErrorResponse(from: decoder))
        case .unknown:
            self = .unknown(try InternalUnknownErrorResponse(from: decoder))
        default:
            throw internalUnexpectedErrorCode(
                discriminator.errorCode,
                for: "InternalBadRequestErrorResponse",
                codingPath: decoder.codingPath
            )
        }
    }

    internal func toFailure<T>(
        invalidArgument: (ErrorCode, String) -> T,
        unknown: (ErrorCode, String) -> T
    ) -> T {
        switch self {
        case .invalidArgument(let response):
            return invalidArgument(response.errorCode.toDomainModel(), response.message)
        case .unknown(let response):
            return unknown(response.errorCode.toDomainModel(), response.message)
        }
    }
}
