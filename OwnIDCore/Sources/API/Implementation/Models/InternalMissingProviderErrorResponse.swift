import Foundation

/// About: No provider is configured for the capability required by the operation, e.g. send SMS for phone-verification.
/// End-user: Not Applicable.
/// Developer action: Configure the missing provider capability for the app and deployment environment.
///
/// OpenAPI source: `MissingProviderError` schema.
internal struct InternalMissingProviderErrorResponse: Sendable, Codable, Hashable {
    internal private(set) var errorCode: InternalErrorCode
    /// Human-readable diagnostic message.
    internal private(set) var message: String
    internal private(set) var capability: String
    internal private(set) var scope: InternalScopeType

    internal init(errorCode: InternalErrorCode, message: String, capability: String, scope: InternalScopeType) {
        self.errorCode = errorCode
        self.message = message
        self.capability = capability
        self.scope = scope
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case message = "message"
        case capability = "capability"
        case scope = "scope"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
        try container.encode(capability, forKey: .capability)
        try container.encode(scope, forKey: .scope)
    }
}
