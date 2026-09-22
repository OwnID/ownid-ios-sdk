import Foundation

/// Process-wide local application and device information exposed through OwnID SDK instances.
///
/// - Values are derived from the host application, device, and bundled module metadata when the SDK first initializes in the process.
/// - Shared by all SDK instances within the current process.
/// - Values can be included in SDK request headers and diagnostic or analytics metadata.
/// - The correlation ID is a process lifetime value for request correlation, not a persisted user or
///   device ID.
/// - Biometric/device flags are for analytics and risk signals only, not access control.
///   The SDK does not pre-block passkey operations based on these flags.
public protocol LocalInfo: Capability, Sendable {
    /// Name/version pairs for Core and optional OwnID modules discoverable when the SDK first initializes in the process (e.g. SwiftUI).
    /// An unavailable module version is reported as `0.0.0`.
    var modules: [(name: String, version: String)] { get }
    /// The application bundle identifier.
    var bundleID: String { get }
    /// The application version string, or `0.0.0` if unavailable.
    var appVersion: String { get }
    /// User-Agent header sent on SDK HTTP requests.
    var userAgent: String { get }
    /// Random Base64URL string generated once per process lifetime and propagated via the baggage header.
    var correlationId: String { get }

    /// Whether the app is built in a debug configuration.
    var isDebuggable: Bool { get }
    /// Whether the OS supports passkeys (iOS 16+).
    var isSystemFidoCapable: Bool { get }

    /// Whether the device is secured with a passcode.
    var isDeviceSecured: Bool { get }
    /// Whether Face ID hardware is available.
    var isFaceHardwarePresent: Bool { get }
    /// Whether Touch ID hardware is available.
    var isFingerprintHardwarePresent: Bool { get }
    /// Whether Face ID or Touch ID can currently be used for authentication on this device.
    var isStrongBiometricEnabled: Bool { get }
}
