import Foundation

/// Provides the resolved base URL for OwnID API requests.
///
/// The returned URL is the API root for the current ``OwnIDConfiguration``. A custom
/// ``OwnIDConfiguration/rootURL`` changes the host/root used by this instance; otherwise the SDK uses the configured
/// app ID, environment, and region.
public protocol APIBaseURL: Capability, Sendable {
    /// Returns the base URL for API calls.
    ///
    /// - Throws: When the URL cannot be resolved from the current configuration.
    func getBaseURL() throws -> URL
}
