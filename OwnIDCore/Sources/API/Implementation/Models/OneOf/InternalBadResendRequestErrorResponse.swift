import Foundation

/// Bad request while resending a verification challenge code.
///
/// OpenAPI source: `BadResendRequestErrorResponse` response.
internal enum InternalBadResendRequestErrorResponse: Sendable, Decodable {
    case invalidArgument(InternalInvalidArgumentErrorResponse)
    case invalidChallenge(InternalInvalidChallengeErrorResponse)
    case maximumResendAttemptsReached(InternalMaximumResendAttemptsReachedErrorResponse)
    case unknown(InternalUnknownErrorResponse)

    internal init(from decoder: Decoder) throws {
        let discriminator = try InternalErrorResponseDiscriminator(from: decoder)
        switch discriminator.errorCode {
        case .invalidArgument:
            self = .invalidArgument(try InternalInvalidArgumentErrorResponse(from: decoder))
        case .invalidChallenge:
            self = .invalidChallenge(try InternalInvalidChallengeErrorResponse(from: decoder))
        case .maximumResendAttemptsReached:
            self = .maximumResendAttemptsReached(try InternalMaximumResendAttemptsReachedErrorResponse(from: decoder))
        case .unknown:
            self = .unknown(try InternalUnknownErrorResponse(from: decoder))
        default:
            throw internalUnexpectedErrorCode(
                discriminator.errorCode,
                for: "InternalBadResendRequestErrorResponse",
                codingPath: decoder.codingPath
            )
        }
    }

    internal func toFailure<T>(
        invalidArgument: (ErrorCode, String) -> T,
        invalidChallenge: (ErrorCode, String, ChallengeID) -> T,
        maximumResendAttemptsReached: (ErrorCode, String, ChallengeID) -> T,
        unknown: (ErrorCode, String) -> T
    ) -> T {
        switch self {
        case .invalidArgument(let response):
            return invalidArgument(response.errorCode.toDomainModel(), response.message)
        case .invalidChallenge(let response):
            return invalidChallenge(response.errorCode.toDomainModel(), response.message, response.challengeId.toDomainModel())
        case .maximumResendAttemptsReached(let response):
            return maximumResendAttemptsReached(response.errorCode.toDomainModel(), response.message, response.challengeId.toDomainModel())
        case .unknown(let response):
            return unknown(response.errorCode.toDomainModel(), response.message)
        }
    }
}
