import Foundation

/// Read-only view of server locale content for one language tag.
///
/// Provides key-path lookup into cached JSON content. Missing keys, missing paths, non-string values, and placeholder
/// entries are exposed as `nil` so callers can continue to embedded string fallbacks.
internal protocol ServerLocaleDataSource: Sendable {
    /// The language tag this data source was loaded for.
    var languageTag: LanguageTag { get }

    /// Resolves a localized string by walking the JSON tree along ``key``.
    ///
    /// Lookup behavior:
    /// - Resolves parent objects along the path.
    /// - At each resolved level (from deepest to root), prefers `<valueKey>-ios` over `<valueKey>`.
    /// - Returns the first match found; otherwise returns `nil`.
    func getString(key: String...) -> String?
}

/// Supplies ``ServerLocaleDataSource`` values as a reactive stream per language tag.
internal protocol ServerLocaleDataSourceProvider: Sendable {
    /// Returns a stream of locale data sources for `languageTag`.
    ///
    /// The stream emits `nil` when no locale JSON content is currently available for the tag, including a missing server
    /// locale, unreadable persisted value, or suppressed refresh failure without payload.
    func getDataSource(for languageTag: LanguageTag) -> AsyncStream<(any ServerLocaleDataSource)?>
}
