import Foundation

/// UI capability for presenting the platform passkey authentication (assertion) prompt.
///
/// This capability is the boundary between SDK-managed operations and AuthenticationServices. It does not own OwnID
/// challenge state or verification; callers provide server-issued ``AssertionOptions`` and receive the platform passkey
/// outcome as ``PasskeyResult``.
public protocol PasskeyAssertionUI: OperationUI {
    /// Presents the system passkey authentication UI.
    ///
    /// The platform credential provider owns prompt presentation, credential selection, cancellation, and
    /// provider-level errors. The returned ``PasskeyResult`` preserves that boundary so the operation layer can decide
    /// whether to verify, cancel, or fail the OwnID challenge.
    ///
    /// - Parameter options: Server-provided options for the FIDO2 assertion ceremony.
    /// - Returns: The assertion result on success, or ``PasskeyResult`` indicating cancellation or failure. Missing
    ///   dependencies or UI errors are surfaced as ``PasskeyResult/failure(_:)``.
    @MainActor func getCredential(options: AssertionOptions) async -> PasskeyResult<AssertionResult>
}
