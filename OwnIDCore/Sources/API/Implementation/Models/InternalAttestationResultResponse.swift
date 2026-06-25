import Foundation

/// OpenAPI source: `AttestationResultResponse` schema.
///
/// `ownIdData` keeps existing raw JSON handling and is injected from the original response text.
internal struct InternalAttestationResultResponse: Sendable, Decodable, Hashable {
    /// ownidData object to replace the data in the vendor's db
    internal private(set) var ownIdData: String
    /// A signed JWT that can be verified as a proof of successful single operation
    internal private(set) var proofToken: String

    internal init(ownIdData: String = "", proofToken: String) {
        self.ownIdData = ownIdData
        self.proofToken = proofToken
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case proofToken = "proofToken"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ownIdData = ""
        self.proofToken = try container.decode(String.self, forKey: .proofToken)
    }

}
