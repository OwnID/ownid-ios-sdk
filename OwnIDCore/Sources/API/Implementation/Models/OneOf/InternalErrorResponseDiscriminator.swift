import Foundation

/// Minimal discriminator payload shared by OpenAPI error response oneOf decoders.
///
/// OpenAPI source: `ErrorBase` schema `errorCode` property.
///
/// Unsupported raw values are rejected so only the literal `unknown` can select an unknown branch.
internal struct InternalErrorResponseDiscriminator: Sendable, Decodable {
    internal let errorCode: InternalErrorCode

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .errorCode)
        guard let errorCode = InternalErrorCode(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .errorCode,
                in: container,
                debugDescription: "Unsupported errorCode=\(rawValue)"
            )
        }
        self.errorCode = errorCode
    }

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
