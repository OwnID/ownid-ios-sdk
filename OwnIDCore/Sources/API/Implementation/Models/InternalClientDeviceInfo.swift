import Foundation

internal struct InternalClientDeviceInfo: Sendable, Codable, Hashable {
    /// Whether a platform authenticator is available on the device.
    internal private(set) var isPlatformAuthenticatorAvailable: Bool
    /// Whether the client is running inside a WebView.
    internal private(set) var isWebView: Bool
    /// Whether the client is a mobile-native SDK integration.
    internal private(set) var isMobileNative: Bool

    internal init(isPlatformAuthenticatorAvailable: Bool, isWebView: Bool, isMobileNative: Bool) {
        self.isPlatformAuthenticatorAvailable = isPlatformAuthenticatorAvailable
        self.isWebView = isWebView
        self.isMobileNative = isMobileNative
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case isPlatformAuthenticatorAvailable = "isPlatformAuthenticatorAvailable"
        case isWebView = "isWebView"
        case isMobileNative = "isMobileNative"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isPlatformAuthenticatorAvailable, forKey: .isPlatformAuthenticatorAvailable)
        try container.encode(isWebView, forKey: .isWebView)
        try container.encode(isMobileNative, forKey: .isMobileNative)
    }
}
