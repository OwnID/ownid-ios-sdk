import Foundation

/// Configuration that identifies which OwnID tenant and region the SDK targets.
///
/// Use this to point an SDK instance at your OwnID tenant and data-residency region. ``OwnIDConfiguration/appID`` is
/// required, ``OwnIDConfiguration/env`` defaults to ``OwnIDEnv/prod``, ``OwnIDConfiguration/region`` defaults to
/// ``OwnIDRegion/us``, and ``OwnIDConfiguration/rootURL`` optionally overrides the default OwnID server root URL.
///
/// Set ``OwnIDConfiguration/env`` to match the tenant you intend to use (for example, ``OwnIDEnv/uat`` for
/// pre-production testing) and set ``OwnIDConfiguration/region`` to where the tenant was created so requests resolve to
/// the correct regional endpoints and respect data-residency.
public protocol OwnIDConfiguration: Sendable {
    /// OwnID application ID from the OwnID Console; must be non-empty and alphanumeric.
    var appID: String { get }
    /// Target environment. Defaults to ``OwnIDEnv/prod``.
    var env: OwnIDEnv { get }
    /// Data-residency region. Defaults to ``OwnIDRegion/us``.
    var region: OwnIDRegion { get }
    /// Custom HTTPS root URL for OwnID servers.
    var rootURL: String? { get }
}

/// Environment selector for OwnID backend routing.
public enum OwnIDEnv: String, CaseIterable, Decodable, Sendable {
    case prod
    case uat

    /// Decodes values case-insensitively.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let value = OwnIDEnv.allCases.first(where: { $0.rawValue.compare(raw, options: .caseInsensitive) == .orderedSame }) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid value '\(raw)' for 'env'")
        }
    }
}

/// Data-residency region selector for OwnID backend routing.
public enum OwnIDRegion: String, CaseIterable, Decodable, Sendable {
    case us = "US"
    case eu = "EU"

    /// Decodes values case-insensitively.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let value = OwnIDRegion.allCases.first(where: { $0.rawValue.compare(raw, options: .caseInsensitive) == .orderedSame }) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid value '\(raw)' for 'region'")
        }
    }
}

internal enum InternalEnv: String, Sendable {
    case prod
    case uat
    case dev

    init(publicEnv: OwnIDEnv) {
        switch publicEnv {
        case .prod: self = .prod
        case .uat: self = .uat
        }
    }

    var stringPrefix: String {
        switch self {
        case .prod: return ""
        case .uat: return ".uat"
        case .dev: return ".dev"
        }
    }
}

internal struct OwnIDConfigurationImpl: OwnIDConfiguration, Decodable, Sendable {
    let appID: String
    let env: OwnIDEnv
    let region: OwnIDRegion
    let rootURL: String?
    internal var internalEnv: InternalEnv? = nil

    private enum CodingKeys: String, CodingKey { case appID, appId, env, region, rootURL, rootUrl }

    internal init(appID: String, env: OwnIDEnv = .prod, region: OwnIDRegion = .us, rootURL: String? = nil) throws {
        let isAlphanumeric = appID.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil
        guard !appID.isEmpty, isAlphanumeric else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "App ID must be alphanumeric and non-empty")
            )
        }
        self.appID = appID
        self.env = env
        self.region = region
        if let rootURL {
            self.rootURL = try Self.normalizeRootURL(rootURL)
        } else {
            self.rootURL = nil
        }
    }

    internal init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let appID =
            try container.decodeIfPresent(String.self, forKey: .appID)
            ?? container.decodeIfPresent(String.self, forKey: .appId)
            ?? {
                let context = DecodingError.Context(codingPath: [], debugDescription: "Required 'appID' or 'appId' key not found.")
                throw DecodingError.keyNotFound(CodingKeys.appID, context)
            }()
        let env = try container.decodeIfPresent(OwnIDEnv.self, forKey: .env) ?? .prod
        let region = try container.decodeIfPresent(OwnIDRegion.self, forKey: .region) ?? .us
        let rootURL =
            try container.decodeIfPresent(String.self, forKey: .rootURL)
            ?? container.decodeIfPresent(String.self, forKey: .rootUrl)
        try self.init(appID: appID, env: env, region: region, rootURL: rootURL)
    }

    private static func normalizeRootURL(_ rootURL: String) throws -> String {
        guard var components = URLComponents(string: rootURL) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid root URL"))
        }
        guard let scheme = components.scheme else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid root URL"))
        }
        guard scheme.lowercased() == "https" else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Root URL must be https"))
        }
        guard components.host != nil else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid root URL"))
        }
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid root URL"))
        }
        return url.absoluteString
    }
}

/// Programmatic builder for ``OwnIDConfiguration``.
///
/// Use this when you prefer to set values directly in code. ``appID`` is required; ``env`` defaults to
/// ``OwnIDEnv/prod``, ``region`` defaults to ``OwnIDRegion/us``, ``rootURL`` is optional and must use HTTPS, and
/// ``languages`` optionally overrides the root SDK language tags during initialization. Missing required values or
/// invalid values make ``OwnID/initialize(instanceName:block:)`` log the build failure and leave any current named
/// instance unchanged.
public final class OwnIDConfigurationBuilder {
    /// Your OwnID application ID from the OwnID Console. Required.
    public var appID: String = ""
    /// Target environment. Defaults to ``OwnIDEnv/prod``.
    public var env: OwnIDEnv = .prod
    /// Data-residency region (``OwnIDRegion/us`` or ``OwnIDRegion/eu``). Defaults to ``OwnIDRegion/us``.
    public var region: OwnIDRegion = .us
    /// Custom HTTPS root URL for OwnID servers.
    public var rootURL: String? = nil
    /// Optional root SDK language override applied during initialization.
    ///
    /// When set to a non-empty array, these BCP 47 tags replace system language tracking for the process until
    /// ``OwnID/setLanguage(_:)`` is called or the process restarts. An empty array keeps or restores system language
    /// tracking. Leaving this `nil` keeps the current root language mode unchanged.
    public var languages: [String]? = nil

    internal init() {}

    internal func apply(_ block: (OwnIDConfigurationBuilder) -> Void) -> OwnIDConfigurationBuilder {
        block(self)
        return self
    }

    internal func build() throws -> (configuration: any OwnIDConfiguration, languages: [String]?) {
        (
            configuration: try OwnIDConfigurationImpl(appID: appID, env: env, region: region, rootURL: rootURL),
            languages: languages
        )
    }
}

/// Builder that creates ``OwnIDConfiguration`` from a JSON string.
///
/// Use this when configuration is provided at runtime. Empty JSON, malformed JSON, or invalid values make
/// ``OwnID/initializeFromJSON(instanceName:block:)`` log the build failure and leave any current named instance
/// unchanged.
///
/// The JSON object accepts "appID" or "appId" for the app ID, "env", "region", and "rootURL" or "rootUrl". Values
/// for ``OwnIDEnv`` and ``OwnIDRegion`` are decoded case-insensitively. Unknown keys are ignored.
///
/// The optional "languages" key must be an array of BCP 47 language-tag strings. A non-empty array sets an explicit
/// root language override, an empty array keeps or restores system language tracking, and omitting the key keeps the
/// current root language mode unchanged.
public final class OwnIDJSONConfigurationBuilder {
    /// JSON string containing the configuration.
    public var json = ""

    internal init() {}

    internal func apply(_ block: (OwnIDJSONConfigurationBuilder) -> Void) -> OwnIDJSONConfigurationBuilder {
        block(self)
        return self
    }

    internal func build() throws -> (configuration: any OwnIDConfiguration, languages: [String]?) {
        guard !json.isEmpty else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Empty JSON string."))
        }
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        guard let normalizedJSONObject = jsonObject as? [String: Any] else {
            return (configuration: try decoder.decode(OwnIDConfigurationImpl.self, from: data), languages: nil)
        }

        let (env, parsedLanguages) = try normalizedJSONObject.extractConfigurationMetadata()

        if env.compare("dev", options: .caseInsensitive) == .orderedSame {
            var normalizedJSONObject = normalizedJSONObject
            normalizedJSONObject.removeValue(forKey: "env")
            let normalizedData = try JSONSerialization.data(withJSONObject: normalizedJSONObject)

            var configuration = try decoder.decode(OwnIDConfigurationImpl.self, from: normalizedData)
            configuration.internalEnv = .dev
            return (configuration: configuration, languages: parsedLanguages)
        }

        return (configuration: try decoder.decode(OwnIDConfigurationImpl.self, from: data), languages: parsedLanguages)
    }
}

/// Builder that creates ``OwnIDConfiguration`` from a configuration file.
///
/// Use this for plist-backed configuration, for example per-scheme files packaged with your app bundle. The default
/// file name is OwnIDConfig.plist located in the main bundle. Missing, empty, unreadable, or invalid files make
/// ``OwnID/initializeFromFile(instanceName:block:)`` log the build failure and leave any current named instance
/// unchanged.
///
/// The plist must contain "appID" or "appId" for the app ID. It accepts "env", "region", and "rootURL" or "rootUrl";
/// values for ``OwnIDEnv`` and ``OwnIDRegion`` are decoded case-insensitively, and unknown keys are ignored. The
/// optional "languages" key must be an array of BCP 47 language-tag strings. A non-empty languages array sets an
/// explicit root language override, an empty array keeps or restores system language tracking, and omitting the key
/// keeps the current root language mode unchanged.
public final class OwnIDFileConfigurationBuilder {
    /// Custom plist file URL. Defaults to OwnIDConfig.plist in the main bundle.
    public var fileURL: URL? = nil

    internal init() {}

    internal func apply(_ block: (OwnIDFileConfigurationBuilder) -> Void) -> OwnIDFileConfigurationBuilder {
        block(self)
        return self
    }

    internal func build() throws -> (configuration: any OwnIDConfiguration, languages: [String]?) {
        let plistURL: URL

        if let fileURL = fileURL {
            plistURL = fileURL
        } else if let defaultURL = Bundle.main.url(forResource: "OwnIDConfig", withExtension: "plist") {
            plistURL = defaultURL
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: plistURL, options: .mappedIfSafe)
        let plistObject = try PropertyListSerialization.propertyList(from: data, format: nil)
        let languages = try (plistObject as? [String: Any])?.extractLanguages()
        return (configuration: try PropertyListDecoder().decode(OwnIDConfigurationImpl.self, from: data), languages: languages)
    }
}

extension OwnIDConfiguration {
    internal func env() -> InternalEnv {
        (self as? OwnIDConfigurationImpl)?.internalEnv ?? InternalEnv(publicEnv: env)
    }

    internal func toStringPrefix() -> String { env().stringPrefix }

    /// Canonical OwnID app host sent in X-OwnID-AppUrl so backend can resolve the app even when rootURL routes requests
    /// elsewhere.
    internal func appURLHeaderValue() -> String {
        "\(appID).server\(toStringPrefix()).ownid\(region.toStringSuffix()).com"
    }

    internal func storageFileName() -> String {
        "\(env().rawValue.lowercased())_\(region.rawValue.lowercased())_\(appID)"
    }
}

extension OwnIDRegion {
    internal func toStringSuffix() -> String {
        switch self {
        case .us: return ""
        case .eu: return "-eu"
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    fileprivate func extractConfigurationMetadata() throws -> (env: String, languages: [String]?) {
        let env = (self["env"] as? String) ?? ""
        return (env: env, languages: try extractLanguages())
    }

    fileprivate func extractLanguages() throws -> [String]? {
        guard let rawLanguages = self["languages"] else {
            return nil
        }
        guard let languages = rawLanguages as? [String] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Expected 'languages' to be an array of strings")
            )
        }
        return languages
    }
}
