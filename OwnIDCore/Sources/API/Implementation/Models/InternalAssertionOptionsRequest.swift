import Foundation

internal struct InternalAssertionOptionsRequest: Sendable, Codable, Hashable {
    internal private(set) var loginId: InternalLoginId?

    internal init(loginId: InternalLoginId? = nil) {
        self.loginId = loginId
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case loginId = "loginId"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(loginId, forKey: .loginId)
    }
}
