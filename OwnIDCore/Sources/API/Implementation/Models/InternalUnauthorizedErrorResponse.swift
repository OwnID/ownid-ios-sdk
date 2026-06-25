import Foundation

/// About: The caller is missing valid authentication for the operation.
/// End-user: Prompt the user to authenticate again.
/// Developer action: Refresh credentials, verify token forwarding, and avoid retry loops without new credentials.
///
/// OpenAPI source: `UnauthorizedError` schema.
internal struct InternalUnauthorizedErrorResponse: Sendable, Codable, Hashable {
    internal private(set) var errorCode: InternalErrorCode
    /// Human-readable diagnostic message.
    internal private(set) var message: String

    internal init(errorCode: InternalErrorCode, message: String) {
        self.errorCode = errorCode
        self.message = message
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case message = "message"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
    }
}
