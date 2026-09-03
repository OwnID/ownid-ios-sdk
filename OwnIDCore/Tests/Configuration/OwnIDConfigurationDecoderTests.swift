import Foundation
import Testing

@testable import OwnIDCore

// Covers: CFG-020, CFG-040, CFG-060, CFG-070, CFG-230, CFG-240, CFG-250, CFG-260, STORAGE-020
struct OwnIDConfigurationDecoderTests {
    @Test(arguments: ConfigurationSource.missingProductIdentifierCases)
    func `Configuration decoder rejects missing product identifier`(_ source: ConfigurationSource) throws {
        let error = try #require(throws: (any Error).self) {
            try source.build(using: self)
        }
        try assertMissingAppID(error)
    }

    @Test func `JSON selects canonical configuration keys before compatibility aliases`() throws {
        let canonical = try buildJSON(#"{"appId":"123","rootUrl":"https://root.example.com/path?debug=true#fragment"}"#)

        #expect(canonical.configuration.appID == "123")
        #expect(canonical.configuration.env == .prod)
        #expect(canonical.configuration.region == .us)
        #expect(canonical.configuration.rootURL == "https://root.example.com/path")
        #expect(canonical.languages == nil)

        let aliases = try buildJSON(#"{"appID":"Tenant987","rootURL":"https://edge.example.com/base?ignored=1#ignored"}"#)

        #expect(aliases.configuration.appID == "Tenant987")
        #expect(aliases.configuration.env == .prod)
        #expect(aliases.configuration.region == .us)
        #expect(aliases.configuration.rootURL == "https://edge.example.com/base")
        #expect(aliases.languages == nil)

        let both = try buildJSON(
            #"{"appId":"Canonical789","appID":"Alias789","rootUrl":"https://canonical.example.com/root","rootURL":"https://alias.example.com/root"}"#
        )
        #expect(both.configuration.appID == "Canonical789")
        #expect(both.configuration.rootURL == "https://canonical.example.com/root")

        let canonicalNullRoot = try buildJSON(
            #"{"appId":"App123","rootUrl":null,"rootURL":"https://alias.example.com/root"}"#
        )
        #expect(canonicalNullRoot.configuration.rootURL == "https://alias.example.com/root")

        let canonicalNullAppID = try buildJSON(#"{"appId":null,"appID":"Alias123"}"#)
        #expect(canonicalNullAppID.configuration.appID == "Alias123")

        #expect(throws: (any Error).self) {
            try buildJSON(
                #"{"appId":"App123","rootUrl":"http://invalid.example.com/root","rootURL":"https://alias.example.com/root"}"#
            )
        }
    }

    @Test(arguments: ["7", "true", "{}", "[]"])
    func `JSON rejects every selected non-string app ID`(_ invalidAppID: String) throws {
        for json in [
            "{\"appId\":\(invalidAppID),\"appID\":\"ValidAlias123\"}",
            "{\"appID\":\(invalidAppID)}",
        ] {
            #expect(throws: (any Error).self) {
                try buildJSON(json)
            }
        }
    }

    @Test(arguments: ["", " ", "Tenant-1", "Tenant_1", "Ténant1"])
    func `JSON rejects selected canonical and alias app IDs outside the source grammar`(_ invalidAppID: String) {
        for json in [
            #"{"appId":"\#(invalidAppID)","appID":"ValidAlias123"}"#,
            #"{"appID":"\#(invalidAppID)"}"#,
        ] {
            #expect(throws: (any Error).self) {
                try buildJSON(json)
            }
        }
    }

    @Test(arguments: ["appId", "appID"])
    func `JSON accepts numeric strings for canonical and alias app IDs`(_ key: String) throws {
        let result = try buildJSON(#"{"\#(key)":"123456"}"#)

        #expect(result.configuration.appID == "123456")
    }

    @Test func `JSON treats top-level null values as omitted`() throws {
        let result = try buildJSON(
            #"{"appId":"App123","env":null,"region":null,"rootUrl":null,"rootURL":null,"languages":null}"#
        )

        #expect(result.configuration.env == .prod)
        #expect(result.configuration.region == .us)
        #expect(result.configuration.rootURL == nil)
        #expect(result.languages == nil)

        for json in [
            #"{"appId":null}"#,
            #"{"appID":null}"#,
            #"{"appId":null,"appID":null}"#,
        ] {
            let error = try #require(throws: (any Error).self) {
                try buildJSON(json)
            }
            try assertMissingAppID(error)
        }
    }

    @Test func `JSON decodes public environment and region case insensitively`() throws {
        let result = try buildJSON(#"{"appID":"App123","env":"UaT","region":"eU"}"#)

        #expect(result.configuration.env == .uat)
        #expect(result.configuration.region == .eu)
        #expect(result.configuration.env() == .uat)
        #expect(result.configuration.appURLHeaderValue() == "App123.server.uat.ownid-eu.com")
        #expect(result.configuration.storageFileName() == "uat_eu_App123")
    }

    @Test func `JSON separates language metadata from configuration`() throws {
        let explicitLanguages = try buildJSON(#"{"appID":"App123","languages":["en-US","fr-FR"],"unknown":"ignored"}"#)

        #expect(explicitLanguages.configuration.appID == "App123")
        #expect(explicitLanguages.configuration.env == .prod)
        #expect(explicitLanguages.configuration.region == .us)
        #expect(explicitLanguages.languages == ["en-US", "fr-FR"])

        let emptyLanguages = try buildJSON(#"{"appID":"App123","languages":[]}"#)

        #expect(emptyLanguages.configuration.appID == "App123")
        #expect(emptyLanguages.languages == [])

        let omittedLanguages = try buildJSON(#"{"appID":"App123"}"#)

        #expect(omittedLanguages.configuration.appID == "App123")
        #expect(omittedLanguages.languages == nil)
    }

    @Test(arguments: [
        #"{"appID":"App123","languages":["en-US",7]}"#,
        #"{"appID":"App123","languages":["en-US",true]}"#,
        #"{"appID":"App123","languages":["en-US",null]}"#,
        #"{"appID":"App123","languages":["en-US",{}]}"#,
        #"{"appID":"App123","languages":["en-US",[]]}"#,
    ])
    func `JSON rejects non-string language metadata`(_ json: String) throws {
        let error = try #require(throws: (any Error).self) {
            try buildJSON(json)
        }
        let context = try requireDataCorruptedContext(error)

        #expect(context.debugDescription.contains("languages"))
    }

    @Test func `Plist rejects non-string language metadata`() throws {
        let fileURL = try temporaryPlistURL(
            containing: [
                "appID": "App123",
                "languages": ["en-US", 7] as [Any],
            ]
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let error = try #require(throws: (any Error).self) {
            try buildPlist(fileURL: fileURL)
        }
        let context = try requireDataCorruptedContext(error)

        #expect(context.debugDescription.contains("languages"))
    }

    @Test func `JSON supports source-owned internal dev environment`() throws {
        let result = try buildJSON(#"{"appID":"App123","env":"DEV","region":"EU","languages":["de-DE"]}"#)

        #expect(result.configuration.appID == "App123")
        #expect(result.configuration.env == .prod)
        #expect(result.configuration.region == .eu)
        #expect(result.configuration.env() == .dev)
        #expect(result.configuration.appURLHeaderValue() == "App123.server.dev.ownid-eu.com")
        #expect(result.configuration.storageFileName() == "dev_eu_App123")
        #expect(result.languages == ["de-DE"])
    }

    @Test func `JSON rejects out-of-range root URL port`() throws {
        let error = try #require(throws: (any Error).self) {
            try buildJSON(#"{"appID":"App123","rootURL":"https://root.example.com:65536/path"}"#)
        }
        _ = try requireDataCorruptedContext(error)
    }

    @Test func `Plist decodes aliases case-insensitive values and language metadata`() throws {
        let fileURL = try temporaryPlistURL(
            containing: [
                "appId": "Tenant987",
                "env": "uAt",
                "region": "eu",
                "rootUrl": "https://plist.example.com/root?token=secret#fragment",
                "languages": ["es-ES", "it-IT"],
            ]
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try buildPlist(fileURL: fileURL)

        #expect(result.configuration.appID == "Tenant987")
        #expect(result.configuration.env == .uat)
        #expect(result.configuration.region == .eu)
        #expect(result.configuration.rootURL == "https://plist.example.com/root")
        #expect(result.configuration.env() == .uat)
        #expect(result.languages == ["es-ES", "it-IT"])
    }

    @Test func `Plist selects canonical configuration keys before compatibility aliases`() throws {
        let fileURL = try temporaryPlistURL(
            containing: [
                "appId": "Canonical123",
                "appID": "Alias123",
                "rootUrl": "https://canonical-plist.example.com/root?token=secret#fragment",
                "rootURL": "https://alias-plist.example.com/root",
            ]
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try buildPlist(fileURL: fileURL)

        #expect(result.configuration.appID == "Canonical123")
        #expect(result.configuration.env == .prod)
        #expect(result.configuration.region == .us)
        #expect(result.configuration.rootURL == "https://canonical-plist.example.com/root")
        #expect(result.languages == nil)
    }

    @Test func `Plist rejects out-of-range root URL port`() throws {
        let fileURL = try temporaryPlistURL(
            containing: [
                "appID": "App123",
                "rootURL": "https://root.example.com:65536/path",
            ]
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let error = try #require(throws: (any Error).self) {
            try buildPlist(fileURL: fileURL)
        }
        _ = try requireDataCorruptedContext(error)
    }

    @Test(arguments: [
        #"https://trusted.example\@attacker.example/path"#,
        #"https://trusted.example/path\segment"#,
        #"https://trusted.example/path?value=bad\query"#,
        #"https://trusted.example/path#bad\fragment"#,
    ])
    func `All configuration sources reject raw backslashes before root URL parsing`(_ rootURL: String) throws {
        let programmaticBuilder = OwnIDConfigurationBuilder()
        programmaticBuilder.appID = "App123"
        programmaticBuilder.rootURL = rootURL
        let programmaticError = try #require(throws: (any Error).self) {
            try programmaticBuilder.build()
        }
        let programmaticContext = try requireDataCorruptedContext(programmaticError)
        #expect(programmaticContext.debugDescription.contains("backslashes"))

        let jsonRootURL = rootURL.replacingOccurrences(of: "\\", with: "\\\\")
        let jsonError = try #require(throws: (any Error).self) {
            try buildJSON("{\"appID\":\"App123\",\"rootURL\":\"\(jsonRootURL)\"}")
        }
        let jsonContext = try requireDataCorruptedContext(jsonError)
        #expect(jsonContext.debugDescription.contains("backslashes"))

        let fileURL = try temporaryPlistURL(containing: ["appID": "App123", "rootURL": rootURL])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let plistError = try #require(throws: (any Error).self) {
            try buildPlist(fileURL: fileURL)
        }
        let plistContext = try requireDataCorruptedContext(plistError)
        #expect(plistContext.debugDescription.contains("backslashes"))
    }

    fileprivate func buildJSON(_ json: String) throws -> (configuration: any OwnIDConfiguration, languages: [String]?) {
        let builder = OwnIDJSONConfigurationBuilder()
        builder.json = json
        return try builder.build()
    }

    fileprivate func buildPlist(fileURL: URL) throws -> (configuration: any OwnIDConfiguration, languages: [String]?) {
        let builder = OwnIDFileConfigurationBuilder()
        builder.fileURL = fileURL
        return try builder.build()
    }

    fileprivate func temporaryPlistURL(containing object: [String: Any]) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OwnIDConfigurationDecoderTests-\(UUID().uuidString)")
            .appendingPathExtension("plist")
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try data.write(to: fileURL)
        return fileURL
    }

    private func assertMissingAppID(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        guard case DecodingError.keyNotFound(let key, let context) = error else {
            throw ConfigurationDecoderFailure("Expected keyNotFound for missing app ID, got \(error)")
        }

        #expect(key.stringValue == "appID", sourceLocation: sourceLocation)
        #expect(context.codingPath.isEmpty, sourceLocation: sourceLocation)
    }

    private func requireDataCorruptedContext(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> DecodingError.Context {
        guard case DecodingError.dataCorrupted(let context) = error else {
            return try #require(
                nil as DecodingError.Context?,
                "Expected dataCorrupted for invalid configuration, got \(error)",
                sourceLocation: sourceLocation
            )
        }

        return context
    }
}

private struct ConfigurationDecoderFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

enum ConfigurationSource: Sendable, CustomTestStringConvertible {
    case jsonMissingProductIdentifier
    case plistMissingProductIdentifier

    static let missingProductIdentifierCases: [ConfigurationSource] = [
        .jsonMissingProductIdentifier,
        .plistMissingProductIdentifier,
    ]

    var testDescription: String {
        switch self {
        case .jsonMissingProductIdentifier:
            return "json"
        case .plistMissingProductIdentifier:
            return "plist"
        }
    }

    func build(
        using tests: OwnIDConfigurationDecoderTests
    ) throws -> (configuration: any OwnIDConfiguration, languages: [String]?) {
        switch self {
        case .jsonMissingProductIdentifier:
            return try tests.buildJSON(#"{"env":"uat","region":"EU"}"#)
        case .plistMissingProductIdentifier:
            let fileURL = try tests.temporaryPlistURL(containing: ["env": "uat", "region": "EU"])
            defer { try? FileManager.default.removeItem(at: fileURL) }
            return try tests.buildPlist(fileURL: fileURL)
        }
    }
}
