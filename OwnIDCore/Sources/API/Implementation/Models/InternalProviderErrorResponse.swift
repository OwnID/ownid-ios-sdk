import Foundation

/// About: A configured provider failed while OwnID was processing the operation, e.g. integration-endpoint failed to fetch the user, email-server failed to send the email.
/// End-user: Show a temporary failure message.
/// Developer action: Log provider request context, monitor the provider integration, and escalate repeated failures.
///
/// OpenAPI source: `ProviderError` schema.
internal struct InternalProviderErrorResponse: Sendable, Codable, Hashable {
    internal private(set) var errorCode: InternalErrorCode
    /// Human-readable diagnostic message.
    internal private(set) var message: String
    internal private(set) var scope: InternalScopeType

    internal init(errorCode: InternalErrorCode, message: String, scope: InternalScopeType) {
        self.errorCode = errorCode
        self.message = message
        self.scope = scope
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case message = "message"
        case scope = "scope"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
        try container.encode(scope, forKey: .scope)
    }
}
