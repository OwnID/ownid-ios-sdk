import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct ServerLocaleDataStoreRuntimeTests {

    @Test func `Persisted server locale content reads from fallback temporary cache using scoped filename`() async throws {
        let tag = LanguageTag(language: "fr", country: "CA")
        let suffix = uniqueSuffix(prefix: "uat_App")
        let fileURL = fallbackCacheFileURL(languageTag: tag, suffix: suffix)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = ServerLocaleDataStore(
            suffix: suffix,
            jsonCoder: JSONCoderImpl(),
            logger: nil,
            forceTemporaryFallback: true
        )
        let content = ServerLocaleContent(
            languageTag: tag,
            content: localeContent(skipPassword: "Serveur", platformSkipPassword: "Serveur iOS")
        )

        try await store.setContent(content, for: tag)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let persisted = try #require(await store.getContent(for: tag))
        #expect(persisted.languageTag == tag)
        #expect(persisted.getString(localeKeys: ["widgets", "sbs-button", "skipPassword"]) == "Serveur iOS")
    }

    @Test func `Corrupted and empty cache files are ignored and removed`() async throws {
        let corruptedTag = LanguageTag(language: "de", country: "DE")
        let emptyTag = LanguageTag(language: "it", country: "")
        let suffix = uniqueSuffix(prefix: "prod_App")
        let corruptedFileURL = fallbackCacheFileURL(languageTag: corruptedTag, suffix: suffix)
        let emptyFileURL = fallbackCacheFileURL(languageTag: emptyTag, suffix: suffix)
        defer {
            try? FileManager.default.removeItem(at: corruptedFileURL)
            try? FileManager.default.removeItem(at: emptyFileURL)
        }

        let store = ServerLocaleDataStore(
            suffix: suffix,
            jsonCoder: JSONCoderImpl(),
            logger: nil,
            forceTemporaryFallback: true
        )
        try FileManager.default.createDirectory(
            at: corruptedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not-json".write(to: corruptedFileURL, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: emptyFileURL.path, contents: Data())

        #expect(await store.getContent(for: corruptedTag) == nil)
        #expect(await store.getContent(for: emptyTag) == nil)
        #expect(!FileManager.default.fileExists(atPath: corruptedFileURL.path))
        #expect(!FileManager.default.fileExists(atPath: emptyFileURL.path))
    }

    @Test func `Placeholder nil locale content persists but remains unusable for string lookup`() async throws {
        let tag = LanguageTag(language: "es", country: "")
        let suffix = uniqueSuffix(prefix: "prod_App")
        let fileURL = fallbackCacheFileURL(languageTag: tag, suffix: suffix)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = ServerLocaleDataStore(
            suffix: suffix,
            jsonCoder: JSONCoderImpl(),
            logger: nil,
            forceTemporaryFallback: true
        )
        let placeholder = ServerLocaleContent(
            languageTag: tag,
            content: nil,
            timeStamp: Date().timeIntervalSince1970,
            backoffUntil: Date().timeIntervalSince1970 + 3_600
        )

        try await store.setContent(placeholder, for: tag)

        let persisted = try #require(await store.getContent(for: tag))
        #expect(persisted.content == nil)
        #expect(persisted.getString(localeKeys: ["widgets", "sbs-button", "skipPassword"]) == nil)
    }
}

private func uniqueSuffix(prefix: String) -> String {
    prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

private func fallbackCacheFileURL(languageTag: LanguageTag, suffix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("com.ownid.sdk/locales/", isDirectory: true)
        .appendingPathComponent("\(languageTag.tagString)_\(suffix).json")
}

private func localeContent(skipPassword: String, platformSkipPassword: String? = nil, or: String = "or") -> [String: JSONValue] {
    var button: [String: JSONValue] = [
        "skipPassword": .string(skipPassword),
        "or": .string(or),
    ]
    if let platformSkipPassword {
        button["skipPassword-ios"] = .string(platformSkipPassword)
    }
    return [
        "widgets": .dictionary([
            "sbs-button": .dictionary(button)
        ])
    ]
}
