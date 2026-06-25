import Foundation

/// UI capability for presenting the platform passkey creation (attestation) prompt.
///
/// This capability is the boundary between SDK-managed operations and AuthenticationServices. It does not own OwnID
/// challenge state or verification; callers provide server-issued ``AttestationOptions`` and receive the platform
/// passkey outcome as ``PasskeyResult``.
public protocol PasskeyAttestationUI: OperationUI {
    /// Presents the system passkey creation UI.
    ///
    /// The platform credential provider owns prompt presentation, credential creation, cancellation, and provider-level
    /// errors. The returned ``PasskeyResult`` preserves that boundary so the operation layer can decide whether to
    /// verify, cancel, or fail the OwnID challenge.
    ///
    /// - Parameter options: Server-provided options for the FIDO2 attestation ceremony.
    /// - Returns: The attestation result on success, or ``PasskeyResult`` indicating cancellation or failure. Missing
    ///   dependencies or UI errors are surfaced as ``PasskeyResult/failure(_:)``.
    @MainActor func createCredential(options: AttestationOptions) async -> PasskeyResult<AttestationResult>
}
