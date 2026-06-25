import Foundation

/// A delivery channel for a verification operation.
///
/// OwnID returns the channel together with a channel ``id`` that identifies it for operation selection. The SDK keeps
/// both strings as supplied; it does not validate, normalize, or unmask them.
///
/// `description` redacts ``channel`` and includes only ``id``. `Codable` uses the public `channel` and `id` keys.
public struct OperationChannel: Codable, Sendable, Hashable, CustomStringConvertible {
    public let channel: String
    public let id: String

    /// Creates an operation channel.
    ///
    /// - Parameters:
    ///   - channel: Channel value, such as an email address or phone number.
    ///   - id: Channel identifier used for operation selection.
    public init(channel: String, id: String) {
        self.channel = channel
        self.id = id
    }

    public var description: String {
        "OperationChannel(channel: '*', id: '\(id)')"
    }
}

/// A recommended operation that can contribute to the current authentication requirements.
///
/// Operation requirements are returned by OwnID as part of ``AuthRequirements``. The SDK keeps the returned ``score`` and
/// ``channels`` as supplied; it does not reject negative scores, duplicate channels, or empty arrays when this model is
/// constructed directly.
///
/// `Codable` uses the public `score`, `type`, and `channels` keys. Unknown operation type strings fail to decode through
/// ``OperationType``.
public struct OperationRequirement: Codable, Sendable, Hashable, CustomStringConvertible {
    public let score: Int
    public let type: OperationType
    public let channels: [OperationChannel]?

    /// Creates an operation requirement.
    ///
    /// - Parameters:
    ///   - score: Score this operation adds toward ``AuthRequirements/targetScore``.
    ///   - type: Operation type to perform.
    ///   - channels: Optional available channels with IDs for performing the operation.
    public init(score: Int, type: OperationType, channels: [OperationChannel]?) {
        self.score = score
        self.type = type
        self.channels = channels
    }

    public var description: String {
        "\(type.rawValue)(score=\(score), channels=[\(channels?.map(\.description).joined(separator: ", ") ?? "nil")])"
    }
}

/// The kind of authentication, enrollment, or account operation.
///
/// `rawValue` is the OwnID operation type string used by API payloads and diagnostics. Swift case names are lower camel
/// case; use `rawValue` when the OwnID string is required. `OperationType(rawValue:)` returns `nil` for unknown strings,
/// and `Codable` decoding fails for unknown raw values.
public enum OperationType: String, Codable, Sendable, CaseIterable {
    case loginIDCollect = "LoginIdCollect"
    case emailVerification = "EmailVerification"
    case emailEnrollment = "EmailEnrollment"
    case phoneNumberVerification = "PhoneNumberVerification"
    case phoneNumberEnrollment = "PhoneNumberEnrollment"
    case passkeyCreation = "PasskeyCreation"
    case passkeyAuth = "PasskeyAuth"
    case passkeyEnrollment = "PasskeyEnrollment"
    case sessionCreation = "SessionCreation"
    case deferredAuthentication = "DeferredAuthentication"
    case externalAuthentication = "ExternalAuthentication"
    case profileCollection = "ProfileCollection"
    case passwordAuthentication = "PasswordAuthentication"
    case oidcAuthenticationApple = "OidcAuthenticationApple"
    case oidcAuthenticationGoogle = "OidcAuthenticationGoogle"
    case registration = "Registration"
    case profileUpdate = "ProfileUpdate"
    case sessionManagement = "SessionManagement"
    case webBridge = "WebBridge"
    case faceKeyVerification = "FaceKeyVerification"
    case faceKeyCreation = "FaceKeyCreation"
    case faceKeyEnrollment = "FaceKeyEnrollment"
}

extension OperationType {
    internal func createOperationID() -> OperationID {
        OperationID(type: self, id: Data.secureRandom().encodeToBase64UrlSafe())
    }
}

/// Unique identifier for one operation lifecycle.
///
/// The SDK creates operation IDs when operations start and uses them to correlate controllers, state, UI presentation,
/// analytics, and results for the same lifecycle. Use ``type`` to inspect the operation kind and ``id`` only as an
/// opaque per-operation identifier. Do not parse ``id`` or treat it as stable beyond the operation run that produced it.
///
/// `description` returns the public `type:id` form using ``OperationType/rawValue``. The initializer keeps ``id`` as
/// supplied and does not reject empty, reused, or externally generated identifiers. `OperationID` is not `Codable`;
/// serialize ``type`` and ``id`` explicitly if an app needs to persist or forward one.
public struct OperationID: Hashable, Sendable, CustomStringConvertible {
    public let type: OperationType
    public let id: String

    /// Creates an operation identifier.
    ///
    /// - Parameters:
    ///   - type: Operation kind associated with this identifier.
    ///   - id: Opaque per-operation identifier.
    public init(type: OperationType, id: String) {
        self.type = type
        self.id = id
    }

    public var description: String {
        "\(type.rawValue):\(id)"
    }
}
