import Foundation

/// Parameters for error string resolution.
///
/// Error strings do not require per-call inputs.
public struct ErrorStringsParams: StringsParams {
    /// Creates error string parameters.
    public init() {}
}

/// Provides resolved error messages keyed by ``ErrorCode``.
///
/// Default SDK providers read error keys from server locale data using the corresponding ``ErrorCode`` values and use
/// ``ErrorStrings/default`` for any missing key.
public protocol ErrorStringsProvider: StringsProvider, Sendable
where D == ErrorStrings, P == ErrorStringsParams {}

/// Repository that supplies complete error strings by applying embedded defaults.
public protocol ErrorStringsEmbeddedRepository: EmbeddedRepository where D == ErrorStrings {}

/// Repository that reads raw error string keys from server locale data.
public protocol ErrorStringsServerRepository: ServerRepository {}

internal final class ErrorStringsProviderImpl: ErrorStringsProvider {
    private let underlyingProvider: AnyStringsProvider<ErrorStrings, ErrorStringsParams>

    init(
        languageTagsProvider: any LanguageTagsProvider,
        embeddedRepository: any ErrorStringsEmbeddedRepository,
        serverRepository: any ErrorStringsServerRepository,
        taskScope: TaskScope
    ) {
        let provider = StringsProviderImpl<ErrorStrings, ErrorStringsParams>(
            languageTagsProvider: languageTagsProvider,
            serverRepository: serverRepository,
            taskScope: taskScope,
            finalMapper: { params, serverStrings in
                return embeddedRepository.fallbackToEmbedded(params: params, map: serverStrings)
            }
        )
        self.underlyingProvider = AnyStringsProvider(provider)
    }

    func getStrings(params: ErrorStringsParams) -> AsyncStream<ErrorStrings?> {
        return underlyingProvider.getStrings(params: params)
    }
}
