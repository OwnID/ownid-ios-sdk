import Foundation
import Testing

@testable import OwnIDCore

struct OwnIDConfigurationDecoderTests {
    @Test(arguments: ConfigurationSource.missingProductIdentifierCases)
    func `Configuration decoder rejects missing product identifier`(_ source: ConfigurationSource) throws {
        let error = try #require(throws: (any Error).self) {
            try source.build(using: self)
        }
        try assertMissingAppID(error)
    }

    @Test func `JSON accepts app ID and root URL aliases with defaults`() throws {
        let canonical = try buildJSON(#"{"appID":"App123","rootURL":"https://root.example.com/path?debug=true#fragment"}"#)

        #expect(canonical.configuration.appID == "App123")
        #expect(canonical.configuration.env == .prod)
        #expect(canonical.configuration.region == .us)
        #expect(canonical.configuration.rootURL == "https://root.example.com/path")
        #expect(canonical.languages == nil)

        let lowerCamel = try buildJSON(#"{"appId":"Tenant987","rootUrl":"https://edge.example.com/base?ignored=1#ignored"}"#)

        #expect(lowerCamel.configuration.appID == "Tenant987")
        #expect(lowerCamel.configuration.env == .prod)
        #expect(lowerCamel.configuration.region == .us)
        #expect(lowerCamel.configuration.rootURL == "https://edge.example.com/base")
        #expect(lowerCamel.languages == nil)
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

    @Test func `JSON rejects non-string language metadata`() throws {
        let error = try #require(throws: (any Error).self) {
            try buildJSON(#"{"appID":"App123","languages":["en-US",7]}"#)
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
                "Expected dataCorrupted for invalid languages, got \(error)",
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
