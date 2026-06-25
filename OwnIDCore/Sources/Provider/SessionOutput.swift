import Foundation

/// Host session payload returned from provider callbacks.
public final class SessionOutput: Sendable {
    /// Host-defined session object.
    ///
    /// May be `nil`.
    public let session: (any Sendable)?

    /// Creates a provider session output.
    ///
    /// - Parameter session: Host-defined session object. May be `nil`.
    public init(session: (any Sendable)?) {
        self.session = session
    }
}
