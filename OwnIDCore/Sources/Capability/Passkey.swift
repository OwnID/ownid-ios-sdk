import Foundation

/// Outcome of a passkey operation.
///
/// - ``success(_:)``: credential data is available.
/// - ``failure(_:)``: a provider error occurred.
/// - ``canceled(_:)``: the user or system canceled the operation.
public enum PasskeyResult<R: Sendable>: Sendable {
    /// Failure payload for a passkey operation.
    public enum Error: Sendable {
        /// General passkey failure from AuthenticationServices or SDK result mapping.
        case general(
            _ message: String,
            _ error: (any Swift.Error & Sendable)? = nil,
            _ identifier: PasskeyAuthorizationErrorIdentifier? = nil
        )
        /// No applicable passkey credential is available for the assertion request.
        case passkeysNoCredential(
            _ message: String,
            _ error: (any Swift.Error & Sendable)? = nil,
            _ identifier: PasskeyAuthorizationErrorIdentifier? = nil
        )
    }

    /// Successful result carrying the credential data.
    case success(R)
    /// Canceled by the user or system, with a reason.
    case canceled(Reason)
    /// Failed with an error.
    case failure(Error)
}

extension PasskeyResult.Error: CustomStringConvertible {
    public var identifier: PasskeyAuthorizationErrorIdentifier? {
        switch self {
        case .general(_, _, let identifier): return identifier
        case .passkeysNoCredential(_, _, let identifier): return identifier
        }
    }

    public var description: String {
        switch self {
        case .general(let message, _, let identifier):
            return "Passkey error: [\(identifier?.value ?? "unknown")] \(message)"
        case .passkeysNoCredential(let message, _, let identifier):
            return "Passkey error: [\(identifier?.value ?? "unknown")] \(message)"
        }
    }
}

/// FIDO2/WebAuthn passkey operations (create and get credentials).
///
/// - Only registered on iOS 16+; unavailable on earlier versions.
/// - Overlapping requests on the same capability instance are not supported. If a request is already running,
///   a new one fails immediately.
/// - Calls are `@MainActor` and use ``UIContextProvider`` to supply the AuthenticationServices presentation anchor.
///   If no active window is available, the SDK provides an empty anchor and the platform owns the resulting failure.
/// - Results are ``PasskeyResult/success(_:)``, ``PasskeyResult/canceled(_:)``, or ``PasskeyResult/failure(_:)``.
public protocol PasskeyProtocol: Capability, Sendable {
    /// Retrieves an existing passkey credential (assertion).
    ///
    /// If another passkey request is already running on the same Passkey instance, this call fails immediately.
    ///
    /// - Parameter assertionOptions: Server-provided assertion options.
    /// - Returns: ``PasskeyResult`` with the assertion data, a cancellation, or a failure.
    @MainActor func getCredential(assertionOptions: AssertionOptions) async -> PasskeyResult<AssertionResult>

    /// Creates a new passkey credential (attestation).
    ///
    /// If another passkey request is already running on the same Passkey instance, this call fails immediately.
    ///
    /// - Parameter attestationOptions: Server-provided attestation options.
    /// - Returns: ``PasskeyResult`` with the attestation data, a cancellation, or a failure.
    @MainActor func createCredential(attestationOptions: AttestationOptions) async -> PasskeyResult<AttestationResult>
}

/// Stable OwnID identifiers for AuthenticationServices passkey authorization errors.
public enum PasskeyAuthorizationErrorIdentifier: Sendable, Equatable {
    /// The user or system canceled the authorization flow.
    case canceled
    /// AuthenticationServices reported an invalid response.
    case invalidResponse
    /// The request could not be handled by an available provider.
    case notHandled
    /// AuthenticationServices reported a generic failure.
    case failed
    /// The request required UI but was not allowed to present it.
    case notInteractive
    /// Credential creation matched an excluded credential.
    case matchedExcludedCredential
    /// Credential import failed.
    case credentialImport
    /// Credential export failed.
    case credentialExport
    /// AuthenticationServices prefers Sign in with Apple for this request.
    case preferSignInWithApple
    /// The device is not configured for passkey creation.
    case deviceNotConfiguredForPasskeyCreation
    /// No applicable passkey credential is available.
    case noCredential
    /// Unknown AuthenticationServices error code.
    case code(Int)

    /// String value used in diagnostics and log messages.
    public var value: String {
        switch self {
        case .canceled: return "CanceledError"
        case .invalidResponse: return "InvalidResponseError"
        case .notHandled: return "NotHandledError"
        case .failed: return "FailedError"
        case .notInteractive: return "NotInteractiveError"
        case .matchedExcludedCredential: return "MatchedExcludedCredentialError"
        case .credentialImport: return "CredentialImportError"
        case .credentialExport: return "CredentialExportError"
        case .preferSignInWithApple: return "PreferSignInWithAppleError"
        case .deviceNotConfiguredForPasskeyCreation: return "DeviceNotConfiguredForPasskeyCreationError"
        case .noCredential: return "NoCredential"
        case .code(let raw): return "code-\(raw)"
        }
    }

    internal static func fromAuthorizationErrorCode(_ code: Int) -> PasskeyAuthorizationErrorIdentifier {
        switch code {
        case 1001: return .canceled
        case 1002: return .invalidResponse
        case 1003: return .notHandled
        case 1004: return .failed
        case 1005: return .notInteractive
        case 1006: return .matchedExcludedCredential
        case 1007: return .credentialImport
        case 1008: return .credentialExport
        case 1009: return .preferSignInWithApple
        case 1010: return .deviceNotConfiguredForPasskeyCreation
        default: return .code(code)
        }
    }
}
