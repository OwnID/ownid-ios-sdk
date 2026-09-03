import Foundation

/// Runs best-effort origin and Apple CDN AASA diagnostics for the given relying-party ID.
public protocol PasskeyDiagnostics: Capability, Sendable {
    /// Starts passkey diagnostics for `rpId`.
    ///
    /// Diagnostics are fire-and-forget and are not part of operation settlement.
    /// No cancellation handle is exposed. Results are reported asynchronously through logs, may be partial when
    /// diagnostic checks fail, and do not block, authorize, or retry passkey operations. A `PASS` describes only the
    /// named AASA observation and doesn't prove overall passkey readiness.
    func verify(rpId: String)
}
