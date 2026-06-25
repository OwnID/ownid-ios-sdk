import Foundation

/// Server locale payload for one ``LanguageTag``.
///
/// `nil` content represents a locale entry that is temporarily unavailable and must not be used for string lookup.
/// Callers use ``isExpired()`` to decide whether the entry should be refreshed and ``getString(localeKeys:)`` to resolve
/// server-provided copy before falling back to embedded strings.
///
/// Lookup treats all keys except the last one as the JSON object path. The final key is resolved from the deepest
/// available object back to the root, preferring `<key>-ios` before the shared `<key>` at each level.
internal struct ServerLocaleContent: Codable, Hashable, Equatable, Sendable {
    let languageTag: LanguageTag
    let content: [String: JSONValue]?
    let timeStamp: TimeInterval
    let backoffUntil: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case languageTag, content, timeStamp, backoffUntil
    }

    private static let iosSuffix = "-ios"
    private static let localeCacheTime: TimeInterval = 10 * 60  // 10 minutes

    init(
        languageTag: LanguageTag,
        content: [String: JSONValue]? = nil,
        timeStamp: TimeInterval = Date().timeIntervalSince1970,
        backoffUntil: TimeInterval? = nil
    ) {
        self.languageTag = languageTag
        self.content = content
        self.timeStamp = timeStamp
        self.backoffUntil = backoffUntil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.languageTag = try container.decode(LanguageTag.self, forKey: .languageTag)
        self.timeStamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timeStamp) ?? Date().timeIntervalSince1970
        self.backoffUntil = try container.decodeIfPresent(TimeInterval.self, forKey: .backoffUntil)

        if let base64String = try container.decodeIfPresent(String.self, forKey: .content),
            let data = base64String.decodeBase64UrlSafe()
        {
            self.content = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } else {
            self.content = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(languageTag, forKey: .languageTag)
        try container.encode(timeStamp, forKey: .timeStamp)
        try container.encodeIfPresent(backoffUntil, forKey: .backoffUntil)

        if let content = content {
            let data = try JSONEncoder().encode(content)
            let base64String = data.encodeToBase64UrlSafe(noPadding: false)
            try container.encode(base64String, forKey: .content)
        }
    }

    /// Returns whether the entry should be refreshed, honoring an active missing-locale backoff window.
    func isExpired() -> Bool {
        let now = Date().timeIntervalSince1970
        if let backoffUntil, now < backoffUntil { return false }
        return now - timeStamp > Self.localeCacheTime
    }

    /// Returns a string for `localeKeys` using the server locale lookup rules, or `nil` when no match exists.
    func getString(localeKeys: [String]) -> String? {
        guard let rootNode = self.content, !localeKeys.isEmpty else { return nil }
        guard let valueKey = localeKeys.last else { return nil }
        let pathKeys = localeKeys.dropLast()
        var parentNodes: [[String: JSONValue]] = [rootNode]
        var currentNode = rootNode

        for key in pathKeys {
            if let nextNode = currentNode[key]?.dictionaryValue {
                parentNodes.append(nextNode)
                currentNode = nextNode
            } else {
                break
            }
        }

        let platformValueKey = valueKey + Self.iosSuffix
        for node in parentNodes.reversed() {
            if let platformValue = node[platformValueKey]?.stringValue {
                return platformValue
            }
            if let baseValue = node[valueKey]?.stringValue {
                return baseValue
            }
        }

        return nil
    }
}
