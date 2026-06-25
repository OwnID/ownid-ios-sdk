import Foundation

internal struct InternalEnrollRequest: Sendable, Codable, Hashable {
    /// A signed JWT that contains a verified channel
    internal private(set) var proofToken: String

    internal init(proofToken: String) {
        self.proofToken = proofToken
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case proofToken = "proofToken"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proofToken, forKey: .proofToken)
    }
}
