import Foundation
import LocalAuthentication

/// Process-wide local application and device information exposed through OwnID SDK instances.
///
/// - Values are collected once when the SDK first initializes in the process and do not refresh during that process.
/// - Shared by all SDK instances within the current process.
/// - Values can be included in SDK request headers and diagnostic or analytics metadata.
/// - The correlation ID is a process lifetime value for request correlation, not a persisted user or
///   device ID.
/// - Local authentication values describe collection time and must not be used for access control.
///   The SDK does not pre-block passkey operations based on these values.
/// - Collection does not authenticate the user.
public protocol LocalInfo: Capability, Sendable {
    /// Name/version pairs for Core and optional OwnID modules discoverable when the SDK first initializes in the process (e.g. SwiftUI).
    /// An unavailable module version is reported as `0.0.0`.
    var modules: [(name: String, version: String)] { get }
    /// The application bundle identifier, or `com.unknown.app` if unavailable.
    var bundleID: String { get }
    /// The application version string, or `0.0.0` if unavailable.
    var appVersion: String { get }
    /// User-Agent header sent on SDK HTTP requests.
    var userAgent: String { get }
    /// Random Base64URL string generated once per process lifetime and propagated via the baggage header.
    var correlationId: String { get }

    /// Whether the Core SDK was compiled with the `DEBUG` compilation condition enabled.
    var isDebuggable: Bool { get }
    /// Whether the OS supports passkeys (iOS 16+).
    var isSystemFidoCapable: Bool { get }

    /// The biometric authentication type supported by the device at collection time.
    var biometryType: LABiometryType { get }
    /// Whether biometric authentication passes its availability check at collection time.
    /// This does not guarantee a subsequent authentication will succeed.
    var isBiometryUsable: Bool { get }
    /// Whether biometric identities are enrolled. `nil` on iOS 13–17 or when no biometric mechanism is supported.
    var isBiometryEnrolled: Bool? { get }
    /// Whether biometry is locked out. `nil` on iOS 13–17 or when no biometric mechanism is supported.
    var isBiometryLockedOut: Bool? { get }
    /// The system-localized biometric mechanism name on iOS 18+, or an SDK-provided Face ID/Touch ID name on earlier versions.
    /// `nil` when the mechanism has no available name or no legacy mapping exists.
    var biometryLocalizedName: String? { get }
    /// The biometric mechanism's SF Symbol name, provided by the system on iOS 18+ or an SDK mapping on earlier versions.
    /// This is metadata only; symbol availability and rendering are not validated. `nil` when no name is available.
    var biometryIconSystemName: String? { get }
    /// Whether a device unlock passcode is configured. `nil` when the configuration cannot be determined.
    /// The passcode can be numeric or alphanumeric; this value does not describe authentication readiness.
    var isPasscodeSet: Bool? { get }
}
