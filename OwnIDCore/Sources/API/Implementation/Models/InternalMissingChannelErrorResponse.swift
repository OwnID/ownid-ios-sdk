import Foundation

/// About: The selected verification channel is unavailable for the login ID.
/// End-user: Offer another authentication method or ask the user to update account contact details.
/// Developer action: Check account provider data and channel configuration before retrying.
///
/// OpenAPI source: `MissingChannelError` schema.
internal struct InternalMissingChannelErrorResponse: Sendable, Codable, Hashable {
    internal private(set) var errorCode: InternalErrorCode
    /// Human-readable diagnostic message.
    internal private(set) var message: String
    internal private(set) var loginId: InternalLoginId

    internal init(errorCode: InternalErrorCode, message: String, loginId: InternalLoginId) {
        self.errorCode = errorCode
        self.message = message
        self.loginId = loginId
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case message = "message"
        case loginId = "loginId"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
        try container.encode(loginId, forKey: .loginId)
    }
}
