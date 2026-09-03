import Foundation
import Testing

@testable import OwnIDCore

// Covers: CFG-080, CFG-090, CFG-100
struct OwnIDProgrammaticConfigurationBuilderTests {
    @Test func `Programmatic configuration builder exposes source-owned defaults`() throws {
        let result = try build { builder in
            builder.appID = "App123"
        }

        #expect(result.configuration.appID == "App123")
        #expect(result.configuration.env == .prod)
        #expect(result.configuration.region == .us)
        #expect(result.configuration.rootURL == nil)
        #expect(result.configuration.env() == .prod)
        #expect(result.configuration.appURLHeaderValue() == "App123.server.ownid.com")
        #expect(result.configuration.storageFileName() == "prod_us_App123")
        #expect(result.languages == nil)
    }

    @Test(arguments: ["", "Tenant-1", "Tenant_1", "Tenant 1", "Tenant.example"])
    func `Programmatic configuration builder rejects invalid app IDs`(_ appID: String) throws {
        let error = try #require(throws: (any Error).self) {
            try build { builder in
                builder.appID = appID
            }
        }
        try requireDataCorruptedContext(error)
    }

    @Test(arguments: ["http://root.example.com", "ftp://root.example.com", "root.example.com/path"])
    func `Programmatic configuration builder rejects non-HTTPS root URLs`(_ rootURL: String) throws {
        let error = try #require(throws: (any Error).self) {
            try build { builder in
                builder.appID = "App123"
                builder.rootURL = rootURL
            }
        }
        try requireDataCorruptedContext(error)
    }

    @Test func `Programmatic configuration builder accepts highest valid root URL port`() throws {
        let result = try build { builder in
            builder.appID = "App123"
            builder.rootURL = "https://edge.example.com:65535/root"
        }

        #expect(result.configuration.rootURL == "https://edge.example.com:65535/root")
    }

    @Test(arguments: [0, 65536])
    func `Programmatic configuration builder rejects out-of-range root URL ports`(_ port: Int) throws {
        let error = try #require(throws: (any Error).self) {
            try build { builder in
                builder.appID = "App123"
                builder.rootURL = "https://edge.example.com:\(port)/root"
            }
        }
        try requireDataCorruptedContext(error)
    }

    @Test func `Programmatic configuration builder strips root URL query and fragment`() throws {
        let result = try build { builder in
            builder.appID = "App123"
            builder.env = .uat
            builder.region = .eu
            builder.rootURL = "https://edge.example.com/root/path?token=secret#ignored"
        }

        #expect(result.configuration.appID == "App123")
        #expect(result.configuration.env == .uat)
        #expect(result.configuration.region == .eu)
        #expect(result.configuration.rootURL == "https://edge.example.com/root/path")
        #expect(result.configuration.env() == .uat)
        #expect(result.configuration.appURLHeaderValue() == "App123.server.uat.ownid-eu.com")
        #expect(result.configuration.storageFileName() == "uat_eu_App123")
        #expect(result.languages == nil)
    }

    @Test func `Programmatic configuration builder preserves optional language metadata separately`() throws {
        let explicitLanguages = try build { builder in
            builder.appID = "App123"
            builder.languages = ["es-ES", "it-IT"]
        }
        #expect(explicitLanguages.configuration.appID == "App123")
        #expect(explicitLanguages.languages == ["es-ES", "it-IT"])

        let emptyLanguages = try build { builder in
            builder.appID = "App123"
            builder.languages = []
        }
        #expect(emptyLanguages.configuration.appID == "App123")
        #expect(emptyLanguages.languages == [])
    }

    private func build(
        _ configure: (OwnIDConfigurationBuilder) -> Void
    ) throws -> (configuration: any OwnIDConfiguration, languages: [String]?) {
        let builder = OwnIDConfigurationBuilder()
        configure(builder)
        return try builder.build()
    }

    @discardableResult
    private func requireDataCorruptedContext(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> DecodingError.Context {
        guard case DecodingError.dataCorrupted(let context) = error else {
            return try #require(
                nil as DecodingError.Context?,
                "Expected dataCorrupted for rejected programmatic configuration, got \(error)",
                sourceLocation: sourceLocation
            )
        }

        return context
    }
}
