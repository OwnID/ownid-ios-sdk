import Foundation

/// Parameters for Boost widget string resolution.
///
/// Boost widget strings do not require per-call inputs.
public struct BoostWidgetStringsParams: StringsParams {
    /// Creates Boost widget string parameters.
    public init() {}
}

/// Complete UI strings for Boost widgets.
///
/// - ``skipPassword``: Label for the skip-password button.
/// - ``or``: Separator text between the widget and alternative login options.
public struct BoostWidgetStrings: StringsData {
    /// Embedded English fallback strings used when server locale data is unavailable or incomplete.
    public static var `default`: BoostWidgetStrings {
        BoostWidgetStrings(skipPassword: "Skip Password", or: "or")
    }

    /// Label for the skip-password button.
    public let skipPassword: String
    /// Separator text between the widget and alternative login options.
    public let or: String

    /// Creates Boost widget strings.
    ///
    /// - Parameters:
    ///   - skipPassword: Label for the skip-password button.
    ///   - or: Separator text between the widget and alternative login options.
    public init(skipPassword: String, or: String) {
        self.skipPassword = skipPassword
        self.or = or
    }
}

/// Provides resolved strings for Boost widgets.
///
/// Default SDK providers read Boost widget keys from server locale data and use ``BoostWidgetStrings/default`` for any
/// missing key.
public protocol BoostWidgetStringsProvider: StringsProvider, Sendable
where D == BoostWidgetStrings, P == BoostWidgetStringsParams {}

/// Repository that supplies complete Boost widget strings by applying embedded defaults.
public protocol BoostWidgetStringsEmbeddedRepository: EmbeddedRepository where D == BoostWidgetStrings {}

/// Repository that reads raw Boost widget string keys from server locale data.
public protocol BoostWidgetStringsServerRepository: ServerRepository {}

internal final class WidgetStringsProviderImpl: BoostWidgetStringsProvider {
    private let underlyingProvider: AnyStringsProvider<BoostWidgetStrings, BoostWidgetStringsParams>

    init(
        languageTagsProvider: any LanguageTagsProvider,
        embeddedRepository: any BoostWidgetStringsEmbeddedRepository,
        serverRepository: any BoostWidgetStringsServerRepository,
        taskScope: TaskScope
    ) {
        let provider = StringsProviderImpl<BoostWidgetStrings, BoostWidgetStringsParams>(
            languageTagsProvider: languageTagsProvider,
            serverRepository: serverRepository,
            taskScope: taskScope,
            finalMapper: { params, serverStrings in
                return embeddedRepository.fallbackToEmbedded(params: params, map: serverStrings)
            }
        )
        self.underlyingProvider = AnyStringsProvider(provider)
    }

    func getStrings(params: BoostWidgetStringsParams) -> AsyncStream<BoostWidgetStrings?> {
        return underlyingProvider.getStrings(params: params)
    }
}
