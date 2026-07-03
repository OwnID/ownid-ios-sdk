import Foundation

/// An IETF BCP 47 language tag with a ``language`` code and optional ``country`` code.
///
/// Encodes and decodes to and from its ``tagString`` representation (e.g. "en", "en-US"). Decoded values that do not
/// resolve to a usable language fall back to ``default``.
///
/// App code usually supplies raw BCP 47 strings through configuration or ``OwnID/setLanguage(_:)``; the SDK normalizes
/// those strings into ``LanguageTag`` values.
public struct LanguageTag: Codable, Hashable, Sendable, CustomStringConvertible {
    public let language: String
    public let country: String

    public static let `default` = LanguageTag(language: "en", country: "")

    internal init(language: String, country: String) {
        self.language = language
        self.country = country
    }

    internal static func from(locale: Locale) -> LanguageTag {
        let rawLanguageCode: String
        let countryCode: String

        if #available(iOS 16, *) {
            rawLanguageCode = locale.language.languageCode?.identifier.lowercased() ?? ""
            countryCode = locale.region?.identifier.uppercased() ?? ""
        } else {
            rawLanguageCode = locale.languageCode?.lowercased() ?? ""
            countryCode = locale.regionCode?.uppercased() ?? ""
        }

        let language: String
        switch rawLanguageCode {
        case "iw": language = "he"
        case "in": language = "id"
        case "ji": language = "yi"
        case "", "und": return LanguageTag.default
        default: language = rawLanguageCode
        }

        return LanguageTag(language: language, country: countryCode)
    }

    public func toLanguageOnly() -> LanguageTag {
        return LanguageTag(language: self.language, country: "")
    }

    public var tagString: String {
        country.isEmpty ? language : "\(language)-\(country)"
    }

    public var description: String {
        tagString
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let tag = try container.decode(String.self)
        let locale = Locale(identifier: tag)
        let newTag = LanguageTag.from(locale: locale)
        self.language = newTag.language
        self.country = newTag.country
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tagString)
    }
}
