import Foundation

/// Minimal discriminator payload shared by OpenAPI error response oneOf decoders.
///
/// OpenAPI source: `ErrorBase` schema `errorCode` property.
///
/// Unknown raw error-code values decode to ``InternalErrorCode/unknown`` before oneOf selection.
internal struct InternalErrorResponseDiscriminator: Sendable, Decodable {
    internal let errorCode: InternalErrorCode

    internal enum CodingKeys: String, CodingKey {
        case errorCode
    }
}

internal func internalUnexpectedErrorCode(_ errorCode: InternalErrorCode, for expected: String, codingPath: [any CodingKey])
    -> DecodingError
{
    DecodingError.dataCorrupted(
        DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Unexpected errorCode=\(errorCode.rawValue) for \(expected)"
        )
    )
}

extension InternalChallengeId {
    internal func toDomainModel() -> ChallengeID {
        ChallengeID(value)
    }
}
