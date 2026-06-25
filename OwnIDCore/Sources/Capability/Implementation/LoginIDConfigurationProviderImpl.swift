import Foundation

/// In-memory ``LoginIDConfigurationProvider`` implementation for an OwnID instance.
///
/// The provider stores a server-driven fallback configuration and an optional app-owned override. Reads return the
/// override when present, otherwise the fallback. The instance registered by default starts from
/// ``LoginIDConfiguration/default``.
///
/// All methods are synchronous and internally synchronized, so callers do not need a specific actor. Invalid updates with no
/// supported types are ignored. Valid updates are normalized by preserving the first occurrence of each supported type
/// and dropping validation regexes for types not in the supported list.
internal final class LoginIDConfigurationProviderImpl: LoginIDConfigurationProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var autoConfiguration: LoginIDConfiguration
    private var forcedConfiguration: LoginIDConfiguration?

    internal init(initialConfiguration: LoginIDConfiguration) {
        self.autoConfiguration = LoginIDConfigurationProviderImpl.normalized(initialConfiguration) ?? initialConfiguration
    }

    internal var configuration: LoginIDConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return forcedConfiguration ?? autoConfiguration
    }

    internal func setServerConfiguration(_ configuration: LoginIDConfiguration) {
        guard let normalized = LoginIDConfigurationProviderImpl.normalized(configuration) else { return }
        lock.lock()
        autoConfiguration = normalized
        lock.unlock()
    }

    internal func setConfiguration(_ configuration: LoginIDConfiguration) {
        guard let normalized = LoginIDConfigurationProviderImpl.normalized(configuration) else { return }
        lock.lock()
        forcedConfiguration = normalized
        lock.unlock()
    }

    internal func clearConfiguration() {
        lock.lock()
        forcedConfiguration = nil
        lock.unlock()
    }

    private static func normalized(_ configuration: LoginIDConfiguration) -> LoginIDConfiguration? {
        let supportedTypes = uniqueTypes(configuration.supportedTypes)
        guard !supportedTypes.isEmpty else { return nil }

        let filteredRegexes = configuration.validationRegexes.filter { supportedTypes.contains($0.key) }
        return LoginIDConfiguration(supportedTypes: supportedTypes, validationRegexes: filteredRegexes)
    }

    private static func uniqueTypes(_ types: [LoginIDType]) -> [LoginIDType] {
        var seen = Set<LoginIDType>()
        return types.filter { seen.insert($0).inserted }
    }
}
