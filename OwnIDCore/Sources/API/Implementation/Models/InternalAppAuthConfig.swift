import Foundation

internal struct InternalAppAuthConfig: Sendable, Codable, Hashable {
    /// Application display name
    internal private(set) var displayName: String?
    /// Settings related to login ID types
    internal private(set) var loginIdConfig: [InternalAppAuthConfigLoginIdConfigItem]
    /// WebView configuration delivered with the auth config.
    internal private(set) var webView: InternalWebViewConfig?
    /// UI configuration with theme-specific assets
    internal private(set) var ui: InternalUIConfig?
    /// Server-provided logging level.
    internal private(set) var logLevel: InternalLogLevel?

    internal init(
        displayName: String? = nil,
        loginIdConfig: [InternalAppAuthConfigLoginIdConfigItem],
        webView: InternalWebViewConfig? = nil,
        ui: InternalUIConfig? = nil,
        logLevel: InternalLogLevel? = nil
    ) {
        self.displayName = displayName
        self.loginIdConfig = loginIdConfig
        self.webView = webView
        self.ui = ui
        self.logLevel = logLevel
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case displayName = "displayName"
        case loginIdConfig = "loginIdConfig"
        case webView = "webView"
        case ui = "ui"
        case logLevel = "logLevel"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(loginIdConfig, forKey: .loginIdConfig)
        try container.encodeIfPresent(webView, forKey: .webView)
        try container.encodeIfPresent(ui, forKey: .ui)
        try container.encodeIfPresent(logLevel, forKey: .logLevel)
    }
}
