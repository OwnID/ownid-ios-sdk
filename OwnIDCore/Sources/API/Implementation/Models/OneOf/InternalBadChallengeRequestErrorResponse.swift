import Foundation

/// Bad request against an existing challenge.
///
/// OpenAPI source: `BadChallengeRequestErrorResponse` response.
internal enum InternalBadChallengeRequestErrorResponse: Sendable, Decodable {
    case invalidArgument(InternalInvalidArgumentErrorResponse)
    case invalidChallenge(InternalInvalidChallengeErrorResponse)
    case maximumAttemptsReached(InternalMaximumAttemptsReachedErrorResponse)
    case unknown(InternalUnknownErrorResponse)

    internal init(from decoder: Decoder) throws {
        let discriminator = try InternalErrorResponseDiscriminator(from: decoder)
        switch discriminator.errorCode {
        case .invalidArgument:
            self = .invalidArgument(try InternalInvalidArgumentErrorResponse(from: decoder))
        case .invalidChallenge:
            self = .invalidChallenge(try InternalInvalidChallengeErrorResponse(from: decoder))
        case .maximumAttemptsReached:
            self = .maximumAttemptsReached(try InternalMaximumAttemptsReachedErrorResponse(from: decoder))
        case .unknown:
            self = .unknown(try InternalUnknownErrorResponse(from: decoder))
        default:
            throw internalUnexpectedErrorCode(
                discriminator.errorCode,
                for: "InternalBadChallengeRequestErrorResponse",
                codingPath: decoder.codingPath
            )
        }
    }

    internal func toFailure<T>(
        invalidArgument: (ErrorCode, String) -> T,
        invalidChallenge: (ErrorCode, String, ChallengeID) -> T,
        maximumAttemptsReached: (ErrorCode, String, ChallengeID) -> T,
        unknown: (ErrorCode, String) -> T
    ) -> T {
        switch self {
        case .invalidArgument(let response):
            return invalidArgument(response.errorCode.toDomainModel(), response.message)
        case .invalidChallenge(let response):
            return invalidChallenge(response.errorCode.toDomainModel(), response.message, response.challengeId.toDomainModel())
        case .maximumAttemptsReached(let response):
            return maximumAttemptsReached(response.errorCode.toDomainModel(), response.message, response.challengeId.toDomainModel())
        case .unknown(let response):
            return unknown(response.errorCode.toDomainModel(), response.message)
        }
    }
}
