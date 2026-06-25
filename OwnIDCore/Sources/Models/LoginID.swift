import Foundation

/// A login identifier value with its declared ``type``.
///
/// The initializer stores ``id`` and ``type`` exactly as supplied. It does not trim, normalize, infer, or validate the
/// value. SDK surfaces that consume a login ID validate it against the active ``LoginIDConfiguration`` and surface
/// unsupported or invalid values through their own input-failure result.
///
/// `Codable` encodes this value as an object with `id` and `type`; ``LoginIDType`` uses its raw string value.
public struct LoginID: Codable, Sendable, Equatable, Hashable {
    public let id: String

    public let type: LoginIDType

    public init(id: String, type: LoginIDType) {
        self.id = id
        self.type = type
    }
}

extension LoginID: CustomStringConvertible {
    /// A debug description with the identifier masked according to ``type``.
    ///
    /// Email and phone-number values are masked only when they match the helper's expected shape. Other identifiers are
    /// trimmed before masking. Use ``id`` when the exact value is required.
    public var description: String {
        var maskedId = id
        switch type {
        case .email: maskedId = id.maskEmail()
        case .phoneNumber: maskedId = id.maskPhoneNumber()
        default: maskedId = id.maskID()
        }
        return "LoginID(id: '\(maskedId)', type: \(type))"
    }
}

/// Classification of a login identifier.
///
/// `Codable` uses the raw string values, such as `Email` or `PhoneNumber`. Decoding an unknown raw value fails with the
/// standard `DecodingError` for raw-value enums.
public enum LoginIDType: String, Codable, Sendable, CaseIterable {
    case userName = "UserName"
    case email = "Email"
    case phoneNumber = "PhoneNumber"
    case credentialID = "CredentialId"
    case anonymous = "Anonymous"
    case faceKeyPersonID = "FaceKeyPersonId"

    private static let classificationRegexes: [LoginIDType: NSRegularExpression] = [
        .email: try! NSRegularExpression(pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"),
        .phoneNumber: try! NSRegularExpression(pattern: "^\\+?[1-9]\\d{1,14}$"),
        .userName: try! NSRegularExpression(pattern: "^(?=.*\\S).*$"),
        .credentialID: try! NSRegularExpression(pattern: "^(?=.*\\S).*$"),
        .anonymous: try! NSRegularExpression(pattern: "^(?=.*\\S).*$"),
        .faceKeyPersonID: try! NSRegularExpression(pattern: "^(?=.*\\S).*$"),
    ]

    /// Embedded regex used to classify identifiers for this type.
    ///
    /// The regex is used to infer a type from a raw login ID and as the validation fallback when
    /// ``LoginIDConfiguration/validationRegexes`` has no override for this type. Types without type-specific syntax use
    /// a non-blank value check.
    public var classificationRegex: NSRegularExpression {
        Self.classificationRegexes[self]!
    }
}

/// Authentication method used during a login or registration flow.
///
/// Encoded as a canonical string matching the raw value. Decoding accepts canonical values and legacy aliases for some
/// methods; unrecognized strings decode as ``unknown``.
public enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case otp = "otp"
    case passkey = "passkey"
    case magicLink = "magic-link"
    case password = "password"
    case deferred = "deferred"
    case immediate = "immediate"
    case unknown = "unknown"
    case socialGoogle = "social-google"
    case socialApple = "social-apple"
    case facekey = "facekey"
    // V3 compatibility
    private static let aliases: [String: AuthMethod] = [
        "biometrics": .passkey,
        "desktop-biometrics": .passkey,
        "email-fallback": .otp,
        "sms-fallback": .otp,
    ]

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AuthMethod(rawValue: raw) ?? AuthMethod.aliases[raw] ?? .unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

/// An authenticated user identified by ``loginID`` and the ``authMethod`` used.
///
/// `Codable` includes the raw login ID value. Use ``LoginID/description`` for logs and debug output.
public struct User: Codable, Sendable {
    public let loginID: LoginID
    public let authMethod: AuthMethod

    public init(loginID: LoginID, authMethod: AuthMethod) {
        self.loginID = loginID
        self.authMethod = authMethod
    }
}

/// Describes supported login-ID types and their optional validation regex overrides.
///
/// ``supportedTypes`` defines which login-ID types may be used and the priority order for resolving a raw login ID
/// value.
///
/// ``validationRegexes`` contains optional validation overrides for supported types. A missing key or `nil` value means
/// validation falls back to ``LoginIDType/classificationRegex``.
///
/// The initializer stores values as supplied. SDK configuration providers normalize before use by preserving the first
/// occurrence of each supported type, ignoring empty supported-type lists, and dropping validation entries for
/// unsupported types.
public struct LoginIDConfiguration: Sendable {
    public let supportedTypes: [LoginIDType]

    public let validationRegexes: [LoginIDType: NSRegularExpression?]

    public init(
        supportedTypes: [LoginIDType],
        validationRegexes: [LoginIDType: NSRegularExpression?]
    ) {
        self.supportedTypes = supportedTypes
        self.validationRegexes = validationRegexes
    }

    public static let `default` = LoginIDConfiguration(
        supportedTypes: [.email],
        validationRegexes: [.email: nil]
    )
}

/// Result returned by a login or discover request.
///
/// ``success(_:)`` means OwnID authentication succeeded and returned data for app session integration.
/// ``authRequired(_:)``, ``accountNotFound(_:)``, and ``accountBlocked(_:)`` are mutually exclusive outcomes when a
/// successful login payload is not returned.
///
/// `Codable` uses Swift's synthesized enum representation for app-owned serialization. It is not the backend wire
/// response shape used by SDK network calls.
public enum LoginResponse: Codable, Sendable, CustomStringConvertible {
    case success(Success)
    case authRequired(AuthRequired)
    case accountNotFound(AccountNotFound)
    case accountBlocked(AccountBlocked)

    /// Successful login carrying the access token and session payload for session integration.
    ///
    /// Pass ``sessionPayload`` to your backend as part of session creation. Structured payload values remain JSON text.
    /// If the server returns a plain string, this property contains that string value.
    ///
    /// ``description`` redacts ``sessionPayload`` and uses the redacted ``AccessToken/description`` output.
    public struct Success: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
        public let accessToken: AccessToken
        public let sessionPayload: String

        public init(accessToken: AccessToken, sessionPayload: String) {
            self.accessToken = accessToken
            self.sessionPayload = sessionPayload
        }

        public var description: String {
            "Success(accessToken=\(accessToken), sessionPayload='*')"
        }
    }

    /// A no-session login outcome.
    ///
    /// ``reason`` is an optional server-provided reason for why a successful login payload was not returned.
    public protocol NoSession: Codable, Sendable {
        var reason: String? { get }
    }

    /// Additional authentication is required before a successful login payload can be returned.
    ///
    /// ``authRequirements`` defines the next operations needed to reach the target score.
    public struct AuthRequired: NoSession, Equatable, Hashable, CustomStringConvertible {
        public let authRequirements: AuthRequirements
        public let reason: String?

        public init(authRequirements: AuthRequirements, reason: String? = nil) {
            self.authRequirements = authRequirements
            self.reason = reason
        }

        public var description: String {
            "AuthRequired(\(authRequirements), reason=\(reason ?? "nil"))"
        }
    }

    public struct AccountNotFound: NoSession, Equatable, Hashable, CustomStringConvertible {
        public let reason: String?

        public init(reason: String? = nil) {
            self.reason = reason
        }

        public var description: String {
            "AccountNotFound(reason=\(reason ?? "nil"))"
        }
    }

    public struct AccountBlocked: NoSession, Equatable, Hashable, CustomStringConvertible {
        public let reason: String?

        public init(reason: String? = nil) {
            self.reason = reason
        }

        public var description: String {
            "AccountBlocked(reason=\(reason ?? "nil"))"
        }
    }

    public var description: String {
        switch self {
        case .success(let success):
            return success.description
        case .authRequired(let required):
            return required.description
        case .accountNotFound(let notFound):
            return notFound.description
        case .accountBlocked(let blocked):
            return blocked.description
        }
    }
}

/// Describes the operations required to reach the authentication target score.
///
/// The initializer stores values as supplied and does not enforce non-negative scores or sort ``operations``.
public struct AuthRequirements: Codable, Sendable, Hashable, CustomStringConvertible {
    public let targetScore: Int
    public let operations: [OperationRequirement]

    /// Creates authentication requirements.
    ///
    /// - Parameters:
    ///   - targetScore: Minimum cumulative score that must be reached.
    ///   - operations: Recommended operations that can be performed to reach the target score, in server-provided order.
    public init(targetScore: Int, operations: [OperationRequirement]) {
        self.targetScore = targetScore
        self.operations = operations
    }

    /// Returns `true` when the sum of all operation scores meets or exceeds the ``targetScore``.
    public func isTargetScoreAchievable() -> Bool {
        if targetScore <= 0 { return true }
        if operations.isEmpty { return false }
        return operations.reduce(0) { $0 + $1.score } >= targetScore
    }

    public var description: String {
        "AuthRequirements(targetScore=\(targetScore), operations=\(operations))"
    }
}
