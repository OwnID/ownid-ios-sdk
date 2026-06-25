import Foundation

/// Internal boundary for runtime ``AppConfig``.
///
/// The provider starts a remote fetch during instance bootstrap and waits only for a bounded bootstrap window before
/// resolving a usable configuration. Fallback order is the last stored configuration for the same app/environment,
/// then ``AppConfig/default``.
///
/// The applied payload is the SDK module boundary for runtime rules, UI asset configuration, and diagnostics thresholds.
/// This is not an app-developer integration surface.
internal protocol AppConfigProvider: Capability, Sendable {
    /// Returns the active ``AppConfig``, suspending only until bootstrap produces a value.
    ///
    /// A cold-start caller may wait for the first network attempt, the bootstrap timeout, or an immediate fetch
    /// failure. The returned value is always non-nil. Network success after fallback may update ``configStream`` later.
    ///
    /// - Returns: The current, stored, or default runtime configuration.
    func getOrFetchConfig() async throws -> AppConfig

    /// Stream of applied non-nil ``AppConfig`` values.
    ///
    /// The stream emits the latest value when a subscriber is registered after configuration is available. Existing
    /// subscribers receive bootstrap's fresh, stored, or default configuration, and receive later successful fetches
    /// only when the applied value changes.
    var configStream: AsyncStream<AppConfig> { get }
}
