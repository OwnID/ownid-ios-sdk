import Foundation

internal struct InternalAccessOrProofTokensResponse: Sendable, Codable, Hashable {
    /// A signed JWT that can be verified as a proof of successful operations
    internal private(set) var accessToken: String?
    /// A signed JWT that can be verified as a proof of successful single operation
    internal private(set) var proofToken: String?

    internal init(accessToken: String? = nil, proofToken: String? = nil) {
        self.accessToken = accessToken
        self.proofToken = proofToken
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case accessToken = "accessToken"
        case proofToken = "proofToken"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        self.proofToken = try container.decodeIfPresent(String.self, forKey: .proofToken)
        guard (accessToken != nil) != (proofToken != nil) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "Exactly one of accessToken or proofToken must be present.")
            )
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard (accessToken != nil) != (proofToken != nil) else {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: container.codingPath, debugDescription: "Exactly one of accessToken or proofToken must be present.")
            )
        }
        try container.encodeIfPresent(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(proofToken, forKey: .proofToken)
    }
}
