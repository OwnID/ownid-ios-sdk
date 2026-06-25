import Foundation

/// About: The caller is authenticated but not allowed to perform the operation.
/// End-user: Explain that the action is unavailable or expired.
/// Developer action: Check access token claims or the operation's policy for the required claims.
///
/// OpenAPI source: `ForbiddenError` schema.
internal struct InternalForbiddenErrorResponse: Sendable, Codable, Hashable {
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
