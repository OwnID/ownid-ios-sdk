import Foundation

/// Server-provided options for a WebAuthn assertion (get credential) request.
///
/// The SDK maps these options to AuthenticationServices when using the built-in passkey capability, then sends the
/// resulting ``AssertionResult`` back to OwnID. Base64url fields are opaque WebAuthn values; do not decode, normalize,
/// or persist them unless your backend explicitly owns that behavior.
///
/// Direct API success responses validate ``challenge`` and ``allowCredentials`` IDs as Base64url before exposing this
/// model. Initializers and `Codable` decoding still do not validate blank strings, relying-party format, or manually
/// supplied Base64url values. The built-in iOS passkey capability ignores allow-list descriptors whose IDs cannot be
/// Base64url-decoded.
///
/// ``rpID`` encodes and decodes as the backend key `rpId`. Missing non-optional fields or unknown enum raw values fail
/// decoding. `nil` optional values are omitted during encoding.
///
/// - Parameters:
///   - challenge: Base64url-encoded challenge that the authenticator must sign.
///   - rpID: Relying Party identifier (the passkey's domain).
///   - allowCredentials: Optional allowlist of credential descriptors; when absent, discoverable credentials may be used.
///   - userVerification: Preferred user-verification policy for the authenticator.
///   - timeout: Timeout for both the server challenge and the client UI.
public struct AssertionOptions: Codable, Sendable, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey, Sendable {
        case challenge
        case rpID = "rpId"
        case allowCredentials
        case userVerification
        case timeout
    }

    public var challenge: ChallengeID
    public var rpID: String
    public var allowCredentials: [PublicKeyCredentialDescriptor]?
    public var userVerification: UserVerification?
    public var timeout: Timeout?

    public init(
        challenge: ChallengeID,
        rpID: String,
        allowCredentials: [PublicKeyCredentialDescriptor]? = nil,
        userVerification: UserVerification? = nil,
        timeout: Timeout? = nil
    ) {
        self.challenge = challenge
        self.rpID = rpID
        self.allowCredentials = allowCredentials
        self.userVerification = userVerification
        self.timeout = timeout
    }

    public var description: String {
        "AssertionOptions(challenge=\(challenge), rpID=\(rpID), allowCredentials=\(allowCredentials.map(String.init(describing:)) ?? "nil"), userVerification=\(userVerification.map(String.init(describing:)) ?? "nil"), timeout=\(timeout.map(String.init(describing:)) ?? "nil"))"
    }
}

/// Result of a successful WebAuthn assertion (get credential) operation.
///
/// The fields are encoded for transport back to OwnID and should be treated as opaque WebAuthn response data. When
/// ``authenticatorAttachment`` is `nil`, assertion verification sends `"platform"` to OwnID for compatibility.
/// ``description`` shortens ``id``, but nested response output can still include full response values.
public struct AssertionResult: Codable, Sendable, CustomStringConvertible {
    public let id: String
    public let type: CredentialType
    public let response: AuthenticatorResponse
    public let authenticatorAttachment: AuthenticatorAttachment?

    /// Authenticator output for a successful assertion.
    ///
    /// Values are Base64url-encoded WebAuthn response fields. ``userHandle`` is optional and opaque.
    public struct AuthenticatorResponse: Codable, Sendable, CustomStringConvertible {
        public let clientDataJSON: String
        public let authenticatorData: String
        public let signature: String
        public let userHandle: String?

        public init(clientDataJSON: String, authenticatorData: String, signature: String, userHandle: String?) {
            self.clientDataJSON = clientDataJSON
            self.authenticatorData = authenticatorData
            self.signature = signature
            self.userHandle = userHandle
        }

        public var description: String {
            "AuthenticatorResponse(clientDataJSON=\(clientDataJSON), authenticatorData=\(authenticatorData), signature=\(signature), userHandle=\(userHandle.map { $0.shorten() } ?? "nil"))"
        }
    }

    public init(id: String, type: CredentialType, response: AuthenticatorResponse, authenticatorAttachment: AuthenticatorAttachment?) {
        self.id = id
        self.type = type
        self.response = response
        self.authenticatorAttachment = authenticatorAttachment
    }

    public var description: String {
        "AssertionResult(id=\(id.shorten()), type=\(type), response=\(response), authenticatorAttachment=\(authenticatorAttachment.map(String.init(describing:)) ?? "nil"))"
    }
}

/// Server-provided options for a WebAuthn attestation (create credential) request.
///
/// The SDK maps the AuthenticationServices-supported fields to the built-in passkey capability, then sends the resulting
/// ``AttestationResult`` back to OwnID. Base64url fields are opaque WebAuthn values; do not decode, normalize, or
/// persist them unless your backend explicitly owns that behavior.
///
/// Direct API success responses validate ``challenge``, ``user`` ID, and ``excludeCredentials`` IDs as Base64url with
/// WebAuthn size limits before exposing this model. Initializers and `Codable` decoding still do not validate blank
/// strings, relying-party format, or manually supplied Base64url values.
///
/// This model is `Codable` with WebAuthn JSON field names. Missing non-optional fields or unknown enum raw values fail
/// decoding. `nil` optional values are omitted during encoding.
/// When the server returns no supported public-key algorithms, the SDK defaults to ``KeyAlgorithmType/ES256`` and
/// ``KeyAlgorithmType/RS256``.
///
/// The built-in iOS passkey capability maps ``challenge``, ``rp``, ``user``, ``attestation``, and
/// ``AuthenticatorSelection/userVerification`` to AuthenticationServices. ``excludeCredentials`` is mapped on iOS 17.4
/// and later; descriptors whose IDs cannot be Base64url-decoded are ignored. Other fields remain available for apps
/// using the direct API with their own platform passkey layer.
///
/// - Parameters:
///   - rp: Relying party information for the credential.
///   - user: User account information for the credential.
///   - challenge: Base64url-encoded challenge that the authenticator must sign.
///   - pubKeyCredParams: Supported public key algorithms for credential creation.
///   - attestation: Relying party attestation preference.
///   - authenticatorSelection: Optional authenticator selection criteria.
///   - timeout: Timeout in milliseconds for both the server challenge and the client UI.
///   - excludeCredentials: Optional credentials that should not be re-registered.
public struct AttestationOptions: Codable, Sendable, CustomStringConvertible {
    public let rp: RelayingParty
    public let user: User
    public let challenge: ChallengeID
    public let pubKeyCredParams: [PubKeyCredParams]
    public let attestation: AttestationConveyancePreference?
    public let authenticatorSelection: AuthenticatorSelection?
    public let timeout: Timeout?
    public let excludeCredentials: [PublicKeyCredentialDescriptor]?

    /// WebAuthn Relying Party with its ``id``, usually the passkey domain, and display ``name``.
    ///
    /// Values are forwarded as provided and are not validated by this data holder.
    public struct RelayingParty: Codable, Sendable, CustomStringConvertible {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }

        public var description: String {
            "RelayingParty(id=\(id), name=\(name))"
        }
    }

    /// WebAuthn user account with a Base64url-encoded ``id``, ``name``, and ``displayName``.
    ///
    /// ``id`` is an opaque user handle. This data holder does not validate encoding or size. ``description`` shortens
    /// ``id`` and masks ``name`` and ``displayName``.
    public struct User: Codable, Sendable, CustomStringConvertible {
        public let id: String
        public let name: String
        public let displayName: String

        public init(id: String, name: String, displayName: String) {
            self.id = id
            self.name = name
            self.displayName = displayName
        }

        public var description: String {
            "User(id=\(id.shorten()), name='*', displayName='*')"
        }
    }

    public struct PubKeyCredParams: Codable, Sendable, CustomStringConvertible {
        public let type: CredentialType
        public let alg: KeyAlgorithmType

        public init(type: CredentialType, alg: KeyAlgorithmType) {
            self.type = type
            self.alg = alg
        }

        public var description: String {
            "PubKeyCredParams(type=\(type), alg=\(alg))"
        }
    }

    /// Optional authenticator-selection criteria for credential creation.
    ///
    /// These fields are preserved for direct API callers. The built-in iOS passkey capability maps only
    /// ``userVerification`` for attestation; `nil` uses AuthenticationServices' required verification preference.
    public struct AuthenticatorSelection: Codable, Sendable, CustomStringConvertible {
        public let authenticatorAttachment: AuthenticatorAttachment?
        public let userVerification: UserVerification?
        public let residentKey: ResidentKey?

        public init(authenticatorAttachment: AuthenticatorAttachment?, userVerification: UserVerification?, residentKey: ResidentKey?) {
            self.authenticatorAttachment = authenticatorAttachment
            self.userVerification = userVerification
            self.residentKey = residentKey
        }

        public var description: String {
            "AuthenticatorSelection(authenticatorAttachment=\(authenticatorAttachment.map(String.init(describing:)) ?? "nil"), userVerification=\(userVerification.map(String.init(describing:)) ?? "nil"), residentKey=\(residentKey.map(String.init(describing:)) ?? "nil"))"
        }
    }

    public init(
        rp: RelayingParty,
        user: User,
        challenge: ChallengeID,
        pubKeyCredParams: [PubKeyCredParams],
        attestation: AttestationConveyancePreference?,
        authenticatorSelection: AuthenticatorSelection?,
        timeout: Timeout?,
        excludeCredentials: [PublicKeyCredentialDescriptor]?
    ) {
        self.rp = rp
        self.user = user
        self.challenge = challenge
        self.pubKeyCredParams = pubKeyCredParams
        self.attestation = attestation
        self.authenticatorSelection = authenticatorSelection
        self.timeout = timeout
        self.excludeCredentials = excludeCredentials
    }

    public var description: String {
        "AttestationOptions(rp=\(rp), user=\(user), challenge=\(challenge), pubKeyCredParams=\(pubKeyCredParams), attestation=\(attestation.map(String.init(describing:)) ?? "nil"), authenticatorSelection=\(authenticatorSelection.map(String.init(describing:)) ?? "nil"), timeout=\(timeout.map(String.init(describing:)) ?? "nil"), excludeCredentials=\(excludeCredentials.map(String.init(describing:)) ?? "nil"))"
    }
}

/// Relying party preference for a resident, also called discoverable, credential.
///
/// The value is available to apps using the direct API with their own platform passkey layer.
public enum ResidentKey: String, Codable, Sendable, CustomStringConvertible {
    case required

    case preferred

    case discouraged

    public var description: String { rawValue }
}

/// Relying party preference for attestation conveyance during credential creation.
///
/// The SDK forwards the preference to AuthenticationServices when present. Actual attestation data depends on the
/// platform provider and authenticator.
public enum AttestationConveyancePreference: String, Codable, Sendable, CustomStringConvertible {
    case none

    case direct

    case indirect

    case enterprise

    public var description: String { rawValue }
}

/// Authenticator attachment value exchanged with WebAuthn.
///
/// Values encode as the WebAuthn strings `"platform"` and `"cross-platform"`, and map to AuthenticationServices
/// attachment values when available.
public enum AuthenticatorAttachment: String, Codable, Sendable, CustomStringConvertible {
    case platform

    case crossPlatform = "cross-platform"

    public var description: String { rawValue }
}

/// Public-key credential type accepted by WebAuthn.
///
/// The SDK currently supports only the WebAuthn `"public-key"` value. iOS exposes it as `publicKey`.
public enum CredentialType: String, Codable, Sendable, CustomStringConvertible {
    case publicKey = "public-key"

    public var description: String { rawValue }
}

/// COSE public-key algorithm identifier supported by SDK passkey mapping.
///
/// Attestation options returned by the direct API default to ``ES256`` and ``RS256`` when OwnID returns no supported
/// algorithms.
public enum KeyAlgorithmType: Int, Codable, Sendable, CustomStringConvertible {
    case ES256 = -7
    case RS256 = -257

    public var description: String { String(rawValue) }
}

/// Authenticator transport hint reported by or sent to WebAuthn.
///
/// Transport values are hints for credential selection and reporting. They do not guarantee that the platform provider
/// used a particular transport.
public enum TransportType: String, Codable, Sendable, CustomStringConvertible {
    case usb = "usb"

    case nfc = "nfc"

    case ble = "ble"

    case smartCard = "smart-card"

    case hybrid = "hybrid"

    case `internal` = "internal"

    case cable = "cable"

    public var description: String { rawValue }
}

/// Relying party user-verification requirement.
///
/// The SDK forwards the value to AuthenticationServices when present; the platform provider decides whether
/// verification can be satisfied.
public enum UserVerification: String, Codable, Sendable, CustomStringConvertible {
    case required

    case preferred

    case discouraged

    public var description: String { rawValue }
}

/// Result of a successful WebAuthn attestation (create credential) operation.
///
/// The fields are encoded for transport back to OwnID and should be treated as opaque WebAuthn response data. The SDK
/// does not persist the result. `nil` ``authenticatorAttachment`` values are omitted during attestation verification.
/// ``description`` shortens ``id`` and the attestation object.
public struct AttestationResult: Codable, Sendable, CustomStringConvertible {
    public let id: String
    public let type: CredentialType
    public let response: AuthenticatorResponse
    public let authenticatorAttachment: AuthenticatorAttachment?

    /// Authenticator output for a successful attestation.
    ///
    /// Values are Base64url-encoded WebAuthn response fields. The built-in iOS passkey capability reports `internal`
    /// and `hybrid` transport hints for attestation results.
    public struct AuthenticatorResponse: Codable, Sendable, CustomStringConvertible {
        public let clientDataJSON: String
        public let attestationObject: String
        public let transports: [TransportType]

        public init(clientDataJSON: String, attestationObject: String, transports: [TransportType]) {
            self.clientDataJSON = clientDataJSON
            self.attestationObject = attestationObject
            self.transports = transports
        }

        public var description: String {
            "AuthenticatorResponse(clientDataJSON=\(clientDataJSON), attestationObject=\(attestationObject.shorten()), transports=\(transports))"
        }
    }

    public init(
        id: String,
        type: CredentialType,
        response: AuthenticatorResponse,
        authenticatorAttachment: AuthenticatorAttachment?
    ) {
        self.id = id
        self.type = type
        self.response = response
        self.authenticatorAttachment = authenticatorAttachment
    }

    public var description: String {
        "AttestationResult(id=\(id.shorten()), type=\(type), response=\(response), authenticatorAttachment=\(authenticatorAttachment.map(String.init(describing:)) ?? "nil"))"
    }
}

/// Identifies an existing credential by its ``id``, ``type``, and optional ``transports``.
///
/// ``id`` is an opaque Base64url-encoded credential ID. The initializer does not validate the encoding or size. Direct
/// API option responses validate descriptor IDs before exposing them; when manually constructed descriptors are used
/// with the built-in iOS passkey capability, descriptors whose IDs cannot be Base64url-decoded are ignored while
/// building allowed or excluded credential lists. ``description`` shortens ``id``.
///
/// - Parameters:
///   - id: Base64url-encoded credential ID.
///   - type: Credential type for the descriptor.
///   - transports: Optional authenticator transport hints.
public struct PublicKeyCredentialDescriptor: Codable, Sendable, CustomStringConvertible {
    public let id: String
    public let type: CredentialType
    public let transports: [TransportType]?

    public init(id: String, type: CredentialType, transports: [TransportType]? = nil) {
        self.id = id
        self.type = type
        self.transports = transports
    }

    public var description: String {
        "PublicKeyCredentialDescriptor(type=\(type), id=\(id.shorten()), transports=\(transports.map(String.init(describing:)) ?? "nil"))"
    }
}

/// Server response after a successful attestation.
///
/// This is an OwnID server response, not a WebAuthn provider payload. ``description`` masks ``ownIdData``.
///
/// - Parameters:
///   - proofToken: Proof token for subsequent enrollment.
///   - ownIdData: Value to store or forward to your vendor backend. Structured values remain JSON text. If the server
///     returns a plain string, this property contains that string value.
public struct AttestationResponse: Codable, Sendable, CustomStringConvertible {
    public let proofToken: ProofToken
    public let ownIdData: String

    public var description: String {
        "AttestationResponse(proofToken=\(proofToken), ownIdData='*')"
    }
}
