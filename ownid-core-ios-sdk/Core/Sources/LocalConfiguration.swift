import Foundation

extension OwnID.CoreSDK.LocalConfiguration {
    enum Error: Swift.Error {
        case redirectURLSchemeNotComplete
        case serverURLIsNotComplete
    }
}

extension OwnID.CoreSDK {
    struct LocalConfiguration: Decodable {
        init(appID: OwnID.CoreSDK.AppID, 
             redirectionURL: OwnID.CoreSDK.RedirectionURLString?,
             environment: String?,
             region: String?,
             enableLogging: Bool?,
             rootURL: String?) throws {
            self.environment = environment
            self.appID = appID
            self.redirectionURL = redirectionURL
            self.region = region == "eu" ? "-eu" : ""
            self.enableLogging = enableLogging
            self.rootURL = try Self.sanitizeRootURL(from: rootURL)
            
            if let redirectionURL {
                try check(redirectionURL: redirectionURL)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let appID = try container.decode(String.self, forKey: .appID)
            let env = try container.decodeIfPresent(String.self, forKey: .env)
            let region = try container.decodeIfPresent(String.self, forKey: .region)
            self.appID = appID
            self.environment = env
            self.region = region == "eu" ? "-eu" : ""
            self.redirectionURL = try container.decodeIfPresent(String.self, forKey: .redirectionURL)
            self.enableLogging = try container.decodeIfPresent(Bool.self, forKey: .enableLogging)
            self.rootURL = try Self.sanitizeRootURL(from: try container.decodeIfPresent(String.self, forKey: .rootURL))
            
            if let redirectionURL {
                try check(redirectionURL: redirectionURL)
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case appID = "OwnIDAppID"
            case redirectionURL = "OwnIDRedirectionURL"
            case env = "OwnIDEnv"
            case region = "OwnIDRegion"
            case enableLogging = "EnableLogging"
            case rootURL = "OwnIDRootURL"
        }
        
        var redirectionURL: RedirectionURLString?
        let appID: OwnID.CoreSDK.AppID
        let environment: String?
        let region: String
        let enableLogging: Bool?
        let rootURL: URL?

        var passkeysAutofillEnabled: Bool!
        var supportedLocales: [String]?
        var loginIdSettings: LoginIdSettings?
        var enableRegistrationFromLogin: Bool?
        var logoURL: URL?
        var phoneCodes: [PhoneCode]?
        var origins: Set<String> = []
        var displayName: String?
        var webViewSettings: WebViewSettings?

        private var envSuffix: String {
            guard let env = environment?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { return "" }
            return ["dev", "staging", "uat"].contains(env) ? ".\(env)" : ""
        }

        var appUrl: String { "\(appID).server\(envSuffix).ownid\(region).com" }

        var apiBaseURL: URL { rootURL ?? URL(string: "https://\(appUrl)")! }

        var cdnBaseURL: URL {
            if let rootURL { return rootURL.appendingPathComponent("sdk") }
            return URL(string: "https://cdn\(envSuffix).ownid\(region).com/sdk")!
        }

        var i18nBaseURL: URL {
            if let rootURL { return rootURL.appendingPathComponent("i18n") }
            let env = environment?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let env, ["dev", "staging", "uat"].contains(env) { return URL(string: "https://i18n.\(env).ownid.com")! }
            return URL(string: "https://i18n.prod.ownid.com")!
        }
    }
}

private extension OwnID.CoreSDK.LocalConfiguration {
    
    func check(redirectionURL: String) throws {
        let parts = redirectionURL.components(separatedBy: ":")
        if parts.count < 2 {
            throw OwnID.CoreSDK.LocalConfiguration.Error.redirectURLSchemeNotComplete
        }
        let secondPart = parts[1]
        if secondPart.isEmpty {
            throw OwnID.CoreSDK.LocalConfiguration.Error.redirectURLSchemeNotComplete
        }
    }

    static func sanitizeRootURL(from value: String?) throws -> URL? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let url = URL(string: raw.extendHttpsIfNeeded()), url.scheme?.lowercased() == "https" else {
            throw OwnID.CoreSDK.LocalConfiguration.Error.serverURLIsNotComplete
        }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OwnID.CoreSDK.LocalConfiguration.Error.serverURLIsNotComplete
        }
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }
}
