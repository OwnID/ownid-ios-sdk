import Foundation

/// Reactive strings provider that merges server locale overlays into typed UI strings.
///
/// For each active primary language tag, server maps are combined in this order:
/// - the full primary tag;
/// - the language-only tag, when the primary tag has a country;
/// - ``LanguageTag/default``, unless it is already covered.
///
/// More specific maps win per key. `nil` server emissions are treated as empty maps, so unavailable locale payloads and
/// suppressed refresh failures without usable content fall through to less-specific server maps and then to embedded
/// defaults. The supplied mapper owns the final key-to-type mapping.
///
/// The stream emits complete strings once a mapping is available, suppresses equal consecutive values, cancels the
/// active merge when language tags change, and finishes if instance-scoped work cannot be started.
internal final class StringsProviderImpl<S: StringsData, P: StringsParams>: StringsProvider {

    private let languageTagsProvider: any LanguageTagsProvider
    private let serverRepository: any ServerRepository
    private let taskScope: TaskScope

    private let finalMapper: @Sendable (P, [String: String]) -> S

    public init(
        languageTagsProvider: any LanguageTagsProvider,
        serverRepository: any ServerRepository,
        taskScope: TaskScope,
        finalMapper: @escaping @Sendable (P, [String: String]) -> S
    ) {
        self.languageTagsProvider = languageTagsProvider
        self.serverRepository = serverRepository
        self.taskScope = taskScope
        self.finalMapper = finalMapper
    }

    public func getStrings(params: P) -> AsyncStream<S?> {
        AsyncStream { continuation in
            let languageStreamTask = taskScope.spawn { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                var currentTask: Task<Void, Never>? = nil
                for await tags in self.languageTagsProvider.languageTags {
                    if Task.isCancelled { break }
                    currentTask?.cancel()
                    currentTask = self.taskScope.spawn { [weak self] in
                        guard let self = self else { return }
                        await self.streamStrings(for: tags, params: params, continuation: continuation)
                    }
                }
                currentTask?.cancel()
                continuation.finish()
            }

            if languageStreamTask == nil {
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in languageStreamTask?.cancel() }
        }
    }

    private func streamStrings(for tags: [LanguageTag], params: P, continuation: AsyncStream<S?>.Continuation) async {
        let primaryTag = tags.first ?? .default

        func makeServerStream(for tag: LanguageTag) -> AsyncStream<[String: String]> {
            AsyncStream { continuation in
                let upstream = serverRepository.getStrings(languageTag: tag, params: params)
                let task = taskScope.spawn {
                    for await value in upstream {
                        if Task.isCancelled { break }
                        continuation.yield(value ?? [:])
                    }
                    continuation.finish()
                }
                if task == nil {
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in task?.cancel() }
            }
        }

        let languageOnlyTag = primaryTag.toLanguageOnly()
        let useLanguageOnly = languageOnlyTag != primaryTag
        let useDefault = LanguageTag.default != primaryTag && LanguageTag.default != languageOnlyTag

        let primaryStream = makeServerStream(for: primaryTag)
        let languageOnlyStream = useLanguageOnly ? makeServerStream(for: languageOnlyTag) : nil
        let defaultStream = useDefault ? makeServerStream(for: .default) : nil

        let merger = StringsMerger<S, P>(params: params, mapFinal: finalMapper) { value in
            continuation.yield(value)
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await value in primaryStream {
                    if Task.isCancelled { break }
                    await merger.update(primary: value)
                }
            }

            if let languageOnlyStream {
                group.addTask {
                    for await value in languageOnlyStream {
                        if Task.isCancelled { break }
                        await merger.update(languageOnly: value)
                    }
                }
            }

            if let defaultStream {
                group.addTask {
                    for await value in defaultStream {
                        if Task.isCancelled { break }
                        await merger.update(fallback: value)
                    }
                }
            }
        }

        await merger.cancelDebounce()
    }
}

private actor StringsMerger<S: StringsData, P: StringsParams> {
    private var primary: [String: String] = [:]
    private var languageOnly: [String: String] = [:]
    private var fallback: [String: String] = [:]

    private var last: S? = nil
    private var didEmitFirst = false
    private var debounceTask: Task<Void, Never>? = nil

    private let params: P
    private let mapFinal: @Sendable (P, [String: String]) -> S
    private let yield: @Sendable (S) -> Void

    fileprivate init(params: P, mapFinal: @escaping @Sendable (P, [String: String]) -> S, yield: @escaping @Sendable (S) -> Void) {
        self.params = params
        self.mapFinal = mapFinal
        self.yield = yield
    }

    fileprivate func update(primary: [String: String]? = nil, languageOnly: [String: String]? = nil, fallback: [String: String]? = nil) {
        if let primary { self.primary = primary }
        if let languageOnly { self.languageOnly = languageOnly }
        if let fallback { self.fallback = fallback }

        var merged = self.fallback
        merged.merge(self.languageOnly) { _, new in new }
        merged.merge(self.primary) { _, new in new }

        let value = mapFinal(params, merged)
        guard value != last else { return }

        if !didEmitFirst {
            last = value
            didEmitFirst = true
            yield(value)
        } else {
            debounceTask?.cancel()
            let toEmit = value
            debounceTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
                self.emitNow(toEmit)
            }
        }
    }

    fileprivate func emitNow(_ value: S) {
        if value != last {
            last = value
            yield(value)
        }
    }

    fileprivate func cancelDebounce() { debounceTask?.cancel() }
}
