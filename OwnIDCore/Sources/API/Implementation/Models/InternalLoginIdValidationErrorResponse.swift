import Foundation

/// About: The login ID value does not match the validation rule configured for its type.
/// End-user: Ask the user to correct the identifier.
/// Developer action: Surface the configured regex only in diagnostics and keep client validation aligned with server config.
///
/// OpenAPI source: `LoginIdValidationError` schema.
internal struct InternalLoginIdValidationErrorResponse: Sendable, Codable, Hashable {
    internal private(set) var errorCode: InternalErrorCode
    /// Human-readable diagnostic message.
    internal private(set) var message: String
    internal private(set) var loginId: InternalLoginId
    internal private(set) var regex: String

    internal init(errorCode: InternalErrorCode, message: String, loginId: InternalLoginId, regex: String) {
        self.errorCode = errorCode
        self.message = message
        self.loginId = loginId
        self.regex = regex
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case message = "message"
        case loginId = "loginId"
        case regex = "regex"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
        try container.encode(loginId, forKey: .loginId)
        try container.encode(regex, forKey: .regex)
    }
}
