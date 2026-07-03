import Foundation

/// About: The supplied login ID type is not supported by the app or operation.
/// End-user: Ask for a supported identifier such as email or phone, based on app configuration.
/// Developer action: Compare the requested login ID type with the app's login ID configuration.
///
/// OpenAPI source: `LoginIdTypeNotSupportedError` schema.
internal struct InternalLoginIdTypeNotSupportedErrorResponse: Sendable, Codable, Hashable {
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
