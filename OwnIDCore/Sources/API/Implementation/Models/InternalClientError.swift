import Foundation

internal struct InternalClientError: Sendable, Codable, Hashable {
    internal private(set) var errorCode: String
    internal private(set) var source: String?
    internal private(set) var message: String?

    internal init(errorCode: String, source: String? = nil, message: String? = nil) {
        self.errorCode = errorCode
        self.source = source
        self.message = message
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case source = "source"
        case message = "message"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(message, forKey: .message)
    }
}
