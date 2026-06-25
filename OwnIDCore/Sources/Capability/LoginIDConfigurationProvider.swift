import Foundation

/// Provides the active login ID configuration used to classify and validate login ID values.
///
/// The SDK registers this capability in each instance and updates its server-driven configuration from app config.
/// Calling ``setConfiguration(_:)`` installs an app-owned override for that instance; the override takes precedence
/// until ``clearConfiguration()`` removes it. This provider supplies configuration to login ID models and validators,
/// but it does not imply that login ID values are persisted.
///
/// Implementations should be safe for concurrent SDK reads and updates from different tasks or actors. The built-in
/// provider keeps only in-memory state, ignores configurations with no supported types, preserves the first occurrence
/// of duplicated types, and drops validation entries for unsupported types.
public protocol LoginIDConfigurationProvider: Capability, Sendable {
    /// Active login ID configuration.
    ///
    /// ``LoginIDConfiguration/supportedTypes`` order is used as type resolution priority. A type-specific regex in
    /// ``LoginIDConfiguration/validationRegexes`` overrides that type's default validation rule.
    var configuration: LoginIDConfiguration { get }

    /// Updates the server-driven fallback configuration.
    ///
    /// If an app override is active, the updated server configuration becomes visible only after
    /// ``clearConfiguration()``. The built-in provider ignores invalid configurations that contain no supported types
    /// and keeps the previous state.
    func setServerConfiguration(_ configuration: LoginIDConfiguration)

    /// Sets an app-owned configuration override.
    ///
    /// The override remains active until ``clearConfiguration()``. The built-in provider ignores invalid
    /// configurations that contain no supported types and keeps the previous state.
    func setConfiguration(_ configuration: LoginIDConfiguration)

    /// Removes the app-owned override and returns ``configuration`` to the latest valid server-driven fallback.
    func clearConfiguration()
}
