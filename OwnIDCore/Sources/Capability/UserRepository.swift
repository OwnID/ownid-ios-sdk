import Foundation

/// Persists the last authenticated ``User`` (login ID and auth method).
///
/// The default repository stores the record in SDK-owned storage scoped by the configured storage file name. The SDK
/// treats the value as returning-user state only; it may contain PII, encryption is not added by this capability, and
/// apps that replace it own equivalent protection and retention behavior.
public protocol UserRepository: Capability, Sendable {
    /// Returns the last authenticated user, or `nil` if none is stored.
    ///
    /// - Returns: The last ``User``, or `nil`.
    /// - Throws: On storage read failure.
    func lastUser() async throws -> User?

    /// Stores `user` as the last authenticated user.
    ///
    /// - Throws: On storage write failure.
    func setLastUser(_ user: User) async throws
    /// Removes the stored last-user record.
    func clearLastUser() async
}
