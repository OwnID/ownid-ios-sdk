import Foundation

internal struct InternalLoginResponse: Sendable, Decodable, Hashable {
    /// A signed JWT that can be verified as a proof of successful operations
    internal private(set) var accessToken: String
    /// The session payload, could be of any type, depending on the app and integrations
    internal private(set) var sessionPayload: String

    internal init(accessToken: String, sessionPayload: String = "") {
        self.accessToken = accessToken
        self.sessionPayload = sessionPayload
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case accessToken = "accessToken"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.sessionPayload = ""
    }

}
