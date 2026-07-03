import Foundation

/// Reporter service identifiers used in analytics events.
internal enum InternalReporterService: String, Sendable, Codable, Hashable, CaseIterable {
    case webSdk = "web-sdk"
    case androidSdk = "android-sdk"
    case iosSdk = "ios-sdk"
}
