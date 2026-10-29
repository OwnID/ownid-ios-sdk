import Foundation

/// Internal runtime configuration for one OwnID app/environment.
///
/// Values come from `/api/config/app`, from the stored configuration file, or from ``default`` when no remote/stored
/// configuration can be applied during bootstrap. The model is shared by SDK capabilities for login ID validation,
/// WebView defaults and origin rules, and server-log filtering. It also carries runtime UI asset data.
///
/// This model is not the public app configuration API.
internal struct AppConfig: Codable, Sendable, Equatable {
    internal struct LoginIdConfig: Codable, Sendable, Equatable {
        internal let type: LoginIDType
        internal let regex: String?
    }

    internal struct WebViewConfig: Codable, Sendable, Equatable {
        internal let baseUrl: String?
        internal let html: String?
        internal let allowedOrigins: Set<String>?
    }

    internal struct UIConfig: Codable, Sendable, Equatable {
        internal struct UIThemeConfig: Codable, Sendable, Equatable {
            internal let logoUrl: String?
        }

        internal let `default`: UIThemeConfig
        internal let dark: UIThemeConfig?
    }

    internal enum LogLevel: String, Codable, Sendable, Equatable {
        case error = "Error"
        case warning = "Warning"
        case information = "Information"
        case debug = "Debug"
        case none = "None"
    }

    internal let loginIdConfig: [LoginIdConfig]
    internal let displayName: String?
    internal let webView: WebViewConfig?
    internal let ui: UIConfig?
    internal let logLevel: LogLevel
    /// Instance-local runtime version; the built-in fallback is -1. Never serialized.
    internal let localVersion: Int

    private enum CodingKeys: String, CodingKey {
        case loginIdConfig, displayName, webView, ui, logLevel
    }

    internal init(
        loginIdConfig: [LoginIdConfig],
        displayName: String?,
        webView: WebViewConfig?,
        ui: UIConfig?,
        logLevel: LogLevel,
        localVersion: Int = -1
    ) {
        self.loginIdConfig = loginIdConfig
        self.displayName = displayName
        self.webView = webView
        self.ui = ui
        self.logLevel = logLevel
        self.localVersion = localVersion
    }

    internal init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            loginIdConfig: try values.decode([LoginIdConfig].self, forKey: .loginIdConfig),
            displayName: try values.decodeIfPresent(String.self, forKey: .displayName),
            webView: try values.decodeIfPresent(WebViewConfig.self, forKey: .webView),
            ui: try values.decodeIfPresent(UIConfig.self, forKey: .ui),
            logLevel: try values.decode(LogLevel.self, forKey: .logLevel)
        )
    }

    internal func withLocalVersion(_ localVersion: Int) -> AppConfig {
        AppConfig(
            loginIdConfig: loginIdConfig,
            displayName: displayName,
            webView: webView,
            ui: ui,
            logLevel: logLevel,
            localVersion: localVersion
        )
    }

    /// Built-in fallback used when neither remote nor stored configuration is available.
    internal static let `default` = AppConfig(
        loginIdConfig: LoginIDConfiguration.default.supportedTypes.map { LoginIdConfig(type: $0, regex: nil) },
        displayName: nil,
        webView: nil,
        ui: nil,
        logLevel: .warning
    )
}
