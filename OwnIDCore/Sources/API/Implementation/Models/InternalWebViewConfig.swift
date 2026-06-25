import Foundation

internal struct InternalWebViewConfig: Sendable, Codable, Hashable {
    /// Base URL for the webview
    internal private(set) var baseUrl: String?
    /// HTML content for the webview
    internal private(set) var html: String?
    /// Allowed webview origins
    internal private(set) var allowedOrigins: [String]?

    internal init(baseUrl: String? = nil, html: String? = nil, allowedOrigins: [String]? = nil) {
        self.baseUrl = baseUrl
        self.html = html
        self.allowedOrigins = allowedOrigins
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case baseUrl = "baseUrl"
        case html = "html"
        case allowedOrigins = "allowedOrigins"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(baseUrl, forKey: .baseUrl)
        try container.encodeIfPresent(html, forKey: .html)
        try container.encodeIfPresent(allowedOrigins, forKey: .allowedOrigins)
    }
}
