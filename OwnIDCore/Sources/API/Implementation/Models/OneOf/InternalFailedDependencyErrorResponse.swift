import Foundation

/// Provider or capability dependency failed.
///
/// OpenAPI source: `FailedDependencyErrorResponse` response.
internal enum InternalFailedDependencyErrorResponse: Sendable, Decodable {
    case provider(InternalProviderErrorResponse)
    case missingProvider(InternalMissingProviderErrorResponse)

    internal init(from decoder: Decoder) throws {
        let discriminator = try InternalErrorResponseDiscriminator(from: decoder)
        switch discriminator.errorCode {
        case .integrationError:
            self = .provider(try InternalProviderErrorResponse(from: decoder))
        case .missingCapabilityProvider:
            self = .missingProvider(try InternalMissingProviderErrorResponse(from: decoder))
        default:
            throw internalUnexpectedErrorCode(
                discriminator.errorCode,
                for: "InternalFailedDependencyErrorResponse",
                codingPath: decoder.codingPath
            )
        }
    }

    internal func toFailure<T>(
        provider: (ErrorCode, String, APIFailureScope) -> T,
        missingProvider: (ErrorCode, String, String, APIFailureScope) -> T
    ) -> T {
        switch self {
        case .provider(let response):
            return provider(response.errorCode.toDomainModel(), response.message, response.scope.toDomainModel())
        case .missingProvider(let response):
            return missingProvider(
                response.errorCode.toDomainModel(),
                response.message,
                response.capability,
                response.scope.toDomainModel()
            )
        }
    }
}
