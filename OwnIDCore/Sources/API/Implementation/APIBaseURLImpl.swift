import Foundation

/// Resolves the instance API base URL from SDK configuration.
///
/// A configured root URL is treated as the deployment root and the SDK API path is appended to it. Without a root URL,
/// the base URL is derived from the instance app ID, environment prefix, and region suffix. Invalid URL configuration is
/// reported by ``getBaseURL()`` before any endpoint request is created.
internal struct APIBaseURLImpl: APIBaseURL {

    private let baseURL: URL

    internal init(configuration: any OwnIDConfiguration) throws {
        if let rootURL = configuration.rootURL {
            guard let url = URL(string: rootURL) else { throw URLError(.badURL) }
            self.baseURL = url.appendingPathComponent("api")
            return
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(configuration.appID).server\(configuration.toStringPrefix()).ownid\(configuration.region.toStringSuffix()).com"
        components.path = "/api"
        guard let url = components.url else { throw URLError(.badURL) }
        self.baseURL = url
    }

    internal func getBaseURL() throws -> URL { baseURL }

    static func create(resolver: any DIContainerResolver) -> any APIBaseURL {
        do {
            return try APIBaseURLImpl(configuration: try resolver.getOrThrow(type: (any OwnIDConfiguration).self))
        } catch {
            return MissingAPIBaseURL(error: error)
        }
    }

    private struct MissingAPIBaseURL: APIBaseURL, @unchecked Sendable {
        private let error: any Error

        internal init(error: any Error) { self.error = error }

        func getBaseURL() throws -> URL { throw error }
    }
}
