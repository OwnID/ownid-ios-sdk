import Foundation

/// UI configuration with theme-specific assets
///
/// OpenAPI source: `UIConfig` schema.
internal struct InternalUIConfig: Sendable, Codable, Hashable {
    internal private(set) var `default`: InternalUIThemeConfig
    internal private(set) var dark: InternalUIThemeConfig?

    internal init(`default`: InternalUIThemeConfig, dark: InternalUIThemeConfig? = nil) {
        self.`default` = `default`
        self.dark = dark
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case `default` = "default"
        case dark = "dark"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(`default`, forKey: .`default`)
        try container.encodeIfPresent(dark, forKey: .dark)
    }
}
