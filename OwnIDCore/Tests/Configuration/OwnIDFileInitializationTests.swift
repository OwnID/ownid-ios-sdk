import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@Suite(.serialized)
struct OwnIDFileInitializationTests {

    @Test func `Explicit plist URL initializes instance with aliases root URL and languages`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("plist-success")
            let appID = Self.uniqueAppID("Tenant")
            let fileURL = try Self.temporaryPlistURL(
                containing: [
                    "appId": appID,
                    "env": "uAt",
                    "region": "eu",
                    "rootUrl": "https://127.0.0.1:9/root?token=secret#fragment",
                    "languages": ["es-ES", "it-IT"],
                ]
            )
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
                try? FileManager.default.removeItem(at: fileURL)
            }

            OwnID.initializeFromFile(instanceName: instanceName) { configuration in
                configuration.fileURL = fileURL
            }

            let instance = OwnID.instance(instanceName: instanceName)

            #expect(instance.configuration.appID == appID)
            #expect(instance.configuration.env == .uat)
            #expect(instance.configuration.region == .eu)
            #expect(instance.configuration.rootURL == "https://127.0.0.1:9/root")
            #expect(!instance.localInfo.bundleID.isEmpty)
            let languageTags = try await Self.currentLanguageTags(for: instanceName)
            #expect(languageTags == ["es-ES", "it-IT"])
        }
    }

    @Test func `Failed plist initialization preserves existing instance configuration and languages`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("plist-failure")
            let appID = Self.uniqueAppID("Stable")
            let originalURL = try Self.temporaryPlistURL(
                containing: [
                    "appID": appID,
                    "env": "prod",
                    "region": "US",
                    "rootURL": "https://127.0.0.1:9/base",
                    "languages": ["de-DE"],
                ]
            )
            let invalidURL = try Self.temporaryPlistURL(
                containing: [
                    "appID": "",
                    "env": "uat",
                    "region": "EU",
                    "rootURL": "https://127.0.0.1:9/mutated",
                    "languages": ["ja-JP"],
                ]
            )
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
                try? FileManager.default.removeItem(at: originalURL)
                try? FileManager.default.removeItem(at: invalidURL)
            }

            OwnID.initializeFromFile(instanceName: instanceName) { configuration in
                configuration.fileURL = originalURL
            }

            OwnID.initializeFromFile(instanceName: instanceName) { configuration in
                configuration.fileURL = invalidURL
            }

            let instance = OwnID.instance(instanceName: instanceName)

            #expect(instance.configuration.appID == appID)
            #expect(instance.configuration.env == .prod)
            #expect(instance.configuration.region == .us)
            #expect(instance.configuration.rootURL == "https://127.0.0.1:9/base")
            let languageTags = try await Self.currentLanguageTags(for: instanceName)
            #expect(languageTags == ["de-DE"])
        }
    }

    @Test func `Missing default bundle plist preserves existing instance configuration and languages`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("default-missing")
            let appID = Self.uniqueAppID("DefaultMissing")
            let originalURL = try Self.temporaryPlistURL(
                containing: [
                    "appID": appID,
                    "env": "prod",
                    "region": "US",
                    "rootURL": "https://127.0.0.1:9/default-base",
                    "languages": ["nl-NL"],
                ]
            )
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
                try? FileManager.default.removeItem(at: originalURL)
            }

            #expect(
                Bundle.main.url(forResource: "OwnIDConfig", withExtension: "plist") == nil,
                "The current package test host has no main-bundle OwnIDConfig.plist; if one is added, cover the default bundle success path instead."
            )

            OwnID.initializeFromFile(instanceName: instanceName) { configuration in
                configuration.fileURL = originalURL
            }
            let beforeContainer = try #require(OwnID.getInstanceContainer(instanceName))
            let beforeID = try Self.containerID(beforeContainer)

            OwnID.initializeFromFile(instanceName: instanceName) { _ in }

            let afterContainer = try #require(OwnID.getInstanceContainer(instanceName))
            let instance = OwnID.instance(instanceName: instanceName)

            let afterID = try Self.containerID(afterContainer)
            #expect(afterID == beforeID)
            #expect(instance.configuration.appID == appID)
            #expect(instance.configuration.env == .prod)
            #expect(instance.configuration.region == .us)
            #expect(instance.configuration.rootURL == "https://127.0.0.1:9/default-base")
            let languageTags = try await Self.currentLanguageTags(for: instanceName)
            #expect(languageTags == ["nl-NL"])
        }
    }

    private static func currentLanguageTags(for instanceName: InstanceName) async throws -> [String] {
        let container = try #require(OwnID.getInstanceContainer(instanceName))
        let provider = try #require(container.getOrNil(type: (any LanguageTagsProvider).self))
        var iterator = provider.languageTags.makeAsyncIterator()
        let tags = try #require(await iterator.next())
        return tags.map(\.tagString)
    }

    private static func containerID(_ container: any DIContainer) throws -> ObjectIdentifier {
        ObjectIdentifier(try #require(container as? DIContainerImpl))
    }

    private static func temporaryPlistURL(containing object: [String: Any]) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OwnIDFileInitializationTests-\(UUID().uuidString)")
            .appendingPathExtension("plist")
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try data.write(to: fileURL)
        return fileURL
    }

    private static func uniqueInstanceName(_ prefix: String) -> InstanceName {
        InstanceName(value: "OwnIDFileInitializationTests-\(prefix)-\(UUID().uuidString)")
    }

    private static func uniqueAppID(_ prefix: String) -> String {
        prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}
