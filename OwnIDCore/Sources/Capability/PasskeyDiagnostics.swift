import Foundation

/// Runs best-effort diagnostic checks for passkey support against the given relying-party ID.
public protocol PasskeyDiagnostics: Capability, Sendable {
    /// Starts passkey diagnostics for `rpId`.
    ///
    /// Diagnostics are fire-and-forget and are not part of operation settlement.
    /// No cancellation handle is exposed. Results are reported asynchronously through logs, may be partial when
    /// diagnostic checks fail, and do not block, authorize, or retry passkey operations.
    func verify(rpId: String)
}
