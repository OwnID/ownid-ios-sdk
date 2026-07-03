import Foundation

internal struct InternalUIThemeConfig: Sendable, Codable, Hashable {
    /// Theme-specific logo URL
    internal private(set) var logoUrl: String?

    internal init(logoUrl: String? = nil) {
        self.logoUrl = logoUrl
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case logoUrl = "logoUrl"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(logoUrl, forKey: .logoUrl)
    }
}
