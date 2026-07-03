import Foundation

/// About: The server could not map the failure to a more specific public error code.
/// End-user: Show a generic failure message and suggest retrying.
/// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
///
/// OpenAPI source: `UnknownError` schema.
internal struct InternalUnknownErrorResponse: Sendable, Codable, Hashable {
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
