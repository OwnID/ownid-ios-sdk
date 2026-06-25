import Foundation

internal struct InternalAssertionResultRequest: Sendable, Codable, Hashable {
    /// Base64url encoded credential ID
    internal private(set) var id: String
    internal private(set) var type: InternalCredentialType
    internal private(set) var response: InternalAssertionAuthenticatorResponse
    internal private(set) var authenticatorAttachment: InternalAuthenticatorAttachment

    internal init(
        id: String,
        type: InternalCredentialType,
        response: InternalAssertionAuthenticatorResponse,
        authenticatorAttachment: InternalAuthenticatorAttachment
    ) {
        self.id = id
        self.type = type
        self.response = response
        self.authenticatorAttachment = authenticatorAttachment
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "id"
        case type = "type"
        case response = "response"
        case authenticatorAttachment = "authenticatorAttachment"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(response, forKey: .response)
        try container.encode(authenticatorAttachment, forKey: .authenticatorAttachment)
    }
}
