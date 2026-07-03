import Foundation

internal struct InternalReporter: Sendable, Codable, Hashable {
    /// Reporter service identifier.
    internal private(set) var service: InternalReporterService
    /// Reporter version string.
    internal private(set) var version: String?
    /// Origin URL of the reporting application.
    internal private(set) var origin: String
    /// Referer URL of the reporting application.
    internal private(set) var referer: String

    internal init(service: InternalReporterService, version: String? = nil, origin: String, referer: String) {
        self.service = service
        self.version = version
        self.origin = origin
        self.referer = referer
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case service = "service"
        case version = "version"
        case origin = "origin"
        case referer = "referer"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(service, forKey: .service)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encode(origin, forKey: .origin)
        try container.encode(referer, forKey: .referer)
    }
}
