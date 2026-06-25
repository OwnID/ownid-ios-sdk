import Foundation

/// Provides resolved strings for SDK-owned UI.
///
/// Default SDK providers combine server locale maps with embedded fallback strings. For the primary
/// ``LanguageTag``, the server-backed provider reads the exact tag first, then its language-only tag when applicable,
/// then ``LanguageTag/default``. Values from the more specific tag win. Missing server keys are filled by the
/// embedded repository before the typed data object is emitted.
///
/// The returned stream updates when the primary language tag or upstream server locale data changes. Server-locale
/// refresh and caching are implementation details; callers observe only typed string data, except for custom providers
/// that choose to emit `nil`.
///
/// - Parameter D: Complete typed string data emitted by the provider.
/// - Parameter P: Parameters that select the operation-specific string variant.
public protocol StringsProvider: Capability, Sendable {
    associatedtype D: StringsData
    associatedtype P: StringsParams

    /// Returns a stream of resolved strings for the given `params`.
    ///
    /// Default server-backed providers emit complete strings after the first mapping. Embedded-only providers emit
    /// complete strings immediately and then finish.
    func getStrings(params: P) -> AsyncStream<D?>
}

/// Marker protocol for operation-specific parameters.
public protocol StringsParams: Sendable {}

/// Marker protocol for a complete operation-specific strings container.
public protocol StringsData: Equatable, Sendable {}

internal struct AnyStringsProvider<D: StringsData, P: StringsParams>: StringsProvider, @unchecked Sendable {
    private let _getStrings: (P) -> AsyncStream<D?>

    init<Provider: StringsProvider>(_ provider: Provider) where Provider.D == D, Provider.P == P {
        self._getStrings = provider.getStrings
    }

    func getStrings(params: P) -> AsyncStream<D?> {
        return _getStrings(params)
    }
}

/// Repository that converts server string keys into complete typed data.
///
/// Implementations fill every missing key from embedded defaults, including the case where the server map is empty.
public protocol EmbeddedRepository: Capability, Sendable {
    associatedtype D: StringsData

    /// Returns complete strings by applying embedded defaults to `map`.
    func fallbackToEmbedded<P: StringsParams>(params: P, map: [String: String]) -> D
}

/// Repository that exposes raw string keys for one server locale payload.
public protocol ServerRepository: Capability, Sendable {
    /// Produces raw localized strings for `languageTag`, or `nil` when no server locale payload is available.
    func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?>
}
