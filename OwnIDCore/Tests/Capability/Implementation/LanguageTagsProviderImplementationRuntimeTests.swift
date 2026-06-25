import Foundation
import Testing

@testable import OwnIDCore

@Suite(.serialized)
struct LanguageTagsProviderImplementationRuntimeTests {

    @Test func `Automatic tracking updates language tags after locale-change notification`() async throws {
        let preferredLanguages = PreferredLanguagesOverride()
        defer { preferredLanguages.restore() }

        preferredLanguages.set(["en-US"])
        let provider = LanguageTagsProviderImpl(logger: nil)
        var iterator = provider.languageTags.makeAsyncIterator()

        #expect(try await Self.nextTagStrings(from: &iterator) == ["en-US"])

        preferredLanguages.set(["fr-FR", "de-DE"])
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        #expect(try await Self.nextTagStrings(from: &iterator) == ["fr-FR", "de-DE"])
    }

    @Test func `Explicit override ignores locale notifications until empty reset restores tracking`() async throws {
        let preferredLanguages = PreferredLanguagesOverride()
        defer { preferredLanguages.restore() }

        preferredLanguages.set(["en-US"])
        let provider = LanguageTagsProviderImpl(logger: nil)
        var iterator = provider.languageTags.makeAsyncIterator()

        #expect(try await Self.nextTagStrings(from: &iterator) == ["en-US"])

        provider.setLanguageTags(["es-ES"])
        #expect(try await Self.nextTagStrings(from: &iterator) == ["es-ES"])

        preferredLanguages.set(["ja-JP"])
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        #expect(try await Self.currentTagStrings(from: provider) == ["es-ES"])

        provider.setLanguageTags([])
        #expect(try await Self.nextTagStrings(from: &iterator) == ["ja-JP"])

        preferredLanguages.set(["it-IT"])
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        #expect(try await Self.nextTagStrings(from: &iterator) == ["it-IT"])
    }

    @Test func `Explicit updates publish to all active language-tag streams`() async throws {
        let preferredLanguages = PreferredLanguagesOverride()
        defer { preferredLanguages.restore() }

        preferredLanguages.set(["en-US"])
        let provider = LanguageTagsProviderImpl(logger: nil)
        var firstIterator = provider.languageTags.makeAsyncIterator()
        var secondIterator = provider.languageTags.makeAsyncIterator()

        #expect(try await Self.nextTagStrings(from: &firstIterator) == ["en-US"])
        #expect(try await Self.nextTagStrings(from: &secondIterator) == ["en-US"])

        provider.setLanguageTags(["de-DE"])

        #expect(try await Self.nextTagStrings(from: &firstIterator) == ["de-DE"])
        #expect(try await Self.nextTagStrings(from: &secondIterator) == ["de-DE"])
    }

    private static func currentTagStrings(from provider: LanguageTagsProviderImpl) async throws -> [String] {
        var iterator = provider.languageTags.makeAsyncIterator()
        return try await nextTagStrings(from: &iterator)
    }

    private static func nextTagStrings(from iterator: inout AsyncStream<[LanguageTag]>.Iterator) async throws -> [String] {
        let tags = try #require(await iterator.next())
        return tags.map(\.tagString)
    }
}

private final class PreferredLanguagesOverride {
    private let originalValue: Any?

    init() {
        originalValue = UserDefaults.standard.object(forKey: "AppleLanguages")
    }

    func set(_ languages: [String]) {
        UserDefaults.standard.set(languages, forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    func restore() {
        if let originalValue {
            UserDefaults.standard.set(originalValue, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}
