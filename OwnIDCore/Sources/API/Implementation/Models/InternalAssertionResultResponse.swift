import Foundation

internal struct InternalAssertionResultResponse: Sendable, Codable, Hashable {
    /// A signed JWT that can be verified as a proof of successful operations
    internal private(set) var accessToken: String

    internal init(accessToken: String) {
        self.accessToken = accessToken
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case accessToken = "accessToken"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
    }
}
