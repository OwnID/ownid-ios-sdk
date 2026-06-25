import Foundation

/// Default ``ServerLocaleDataSourceProvider`` backed by persisted locale entries and network refresh.
///
/// Consumers subscribe per ``LanguageTag`` and receive the currently available server data source, or `nil` when no
/// usable payload exists. Reads may trigger a background refresh while existing usable content remains available. The
/// provider also tracks the active primary language and refreshes the primary, language-only, and default fallback tags
/// for the instance.
///
/// Refresh results are surfaced through the stream rather than thrown to callers. Missing server locales and suppressed
/// refresh failures are represented as `nil` or as previously cached content when usable content exists. Network
/// failures do not clear existing content. Callers must continue to resolve embedded defaults for missing streams or
/// missing individual keys.
final internal class ServerLocaleDataSourceProviderImpl: ServerLocaleDataSourceProvider {

    private let configuration: any OwnIDConfiguration
    private let network: any NetworkProtocol
    private let languageTagsProvider: any LanguageTagsProvider
    private let dataStore: ServerLocaleDataStore
    private let logger: OwnIDLogRouter?
    private let stateActor = StateActor()
    private let taskScope: TaskScope
    private let observeTagsTask: Task<Void, Never>?

    private var baseLocaleUrl: URL {
        if let rootURL = configuration.rootURL, let baseURL = URL(string: rootURL) {
            return baseURL.appendingPathComponent("i18n")
        }
        return URL(string: "https://i18n.\(configuration.env().rawValue).ownid.com")!
    }

    init(
        configuration: any OwnIDConfiguration,
        network: any NetworkProtocol,
        languageTagsProvider: any LanguageTagsProvider,
        jsonCoder: any JSONCoder,
        taskScope: TaskScope,
        logger: OwnIDLogRouter?
    ) {
        self.configuration = configuration
        self.network = network
        self.languageTagsProvider = languageTagsProvider
        self.taskScope = taskScope
        self.logger = logger

        let suffix = "\(configuration.env().rawValue)_\(configuration.appID)"
        self.dataStore = ServerLocaleDataStore(suffix: suffix, jsonCoder: jsonCoder, logger: logger)
        let weakBox = WeakBox<ServerLocaleDataSourceProviderImpl>()
        self.observeTagsTask = taskScope.spawn { [weakBox, languageTagsProvider] in
            // A small delay to not add additional load in app startup.
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            var lastSeenPrimaryTag: LanguageTag?
            for await tags in languageTagsProvider.languageTags {
                if Task.isCancelled { break }
                let primaryTag = tags.first ?? .default
                if primaryTag == lastSeenPrimaryTag { continue }
                lastSeenPrimaryTag = primaryTag

                let tagsToUpdate: Set<LanguageTag> = [primaryTag, primaryTag.toLanguageOnly(), .default]

                guard let provider = weakBox.value else { break }
                await withTaskGroup(of: Void.self) { group in
                    for tag in tagsToUpdate {
                        group.addTask { @Sendable in
                            await provider.triggerLocaleUpdate(for: tag)
                        }
                    }
                }
            }
        }
        weakBox.value = self
    }

    /// Returns a stream of locale data sources for `languageTag`.
    ///
    /// New subscribers receive the current usable data source for the tag, or `nil` when no usable payload exists. A
    /// background refresh is triggered for the requested tag; existing usable content may remain visible until a later
    /// refresh result is published.
    func getDataSource(for languageTag: LanguageTag) -> AsyncStream<(any ServerLocaleDataSource)?> {
        _ = taskScope.spawn { [weak self] in
            await self?.triggerLocaleUpdate(for: languageTag)
        }

        return AsyncStream<(any ServerLocaleDataSource)?> { continuation in
            let id = UUID()
            Task {
                let initialData = await stateActor.register(continuation, for: languageTag, id: id)

                if let initialData {
                    continuation.yield(initialData)
                } else if let diskContent = await dataStore.getContent(for: languageTag) {
                    let dataSource = makeDataSource(for: languageTag, content: diskContent)
                    await stateActor.updateCache(with: dataSource, for: languageTag)
                    continuation.yield(dataSource)
                } else {
                    continuation.yield(nil)
                }
            }

            continuation.onTermination = { _ in
                Task { await self.stateActor.unregister(id: id, for: languageTag) }
            }
        }
    }

    deinit {
        observeTagsTask?.cancel()
    }

    /// Starts a best-effort refresh for `languageTag` when the current entry should be refreshed.
    private func triggerLocaleUpdate(for languageTag: LanguageTag) async {
        guard await stateActor.reserveUpdate(for: languageTag) else {
            logger?.logV(source: self, prefix: #function, message: "Update job already in progress for [\(languageTag)]. Skipping")
            return
        }

        guard
            let task = taskScope.spawn({ [weak self] in
                guard let self else { return }
                defer {
                    Task { await self.stateActor.finishUpdate(for: languageTag) }
                    self.logger?.logV(source: self, prefix: #function, message: "Update completed for [\(languageTag)]")
                }
                let existingContent = await self.dataStore.getContent(for: languageTag)
                guard existingContent?.isExpired() ?? true else {
                    self.logger?.logD(source: self, prefix: #function, message: "Cache fresh for [\(languageTag)]. Skipping network")
                    return
                }
                await self.performLocaleUpdate(for: languageTag, existingContent: existingContent)
            })
        else {
            await stateActor.finishUpdate(for: languageTag)
            return
        }
        await stateActor.record(task, for: languageTag)
    }

    /// Fetches locale JSON for `languageTag` and publishes either usable content, `nil`, or the prior usable content.
    private func performLocaleUpdate(for languageTag: LanguageTag, existingContent: ServerLocaleContent?) async {
        let url = baseLocaleUrl.appendingPathComponent(languageTag.tagString).appendingPathComponent("mobile-sdk.json")
        var request = NetworkRequest(url: url)
        request.setMethod(.get)
        let result: NetworkResponse
        do {
            result = try await network.run(request)
        } catch is CancellationError {
            return
        } catch {
            logger?.logW(
                source: self,
                prefix: #function,
                message: "Locale data update failed [\(languageTag)] (\(url.absoluteString))",
                cause: error
            )
            await suppressAfterError(for: languageTag, content: existingContent)
            return
        }

        switch result {
        case .success(let response):
            do {
                guard let data = response.body.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }
                let jsonObject = try JSONDecoder().decode([String: JSONValue].self, from: data)
                let newContent = ServerLocaleContent(languageTag: languageTag, content: jsonObject)
                try await dataStore.setContent(newContent, for: languageTag)
                logger?.logV(source: self, prefix: #function, message: "Locale update success [\(languageTag)]")

                await onUpdateFinished(for: languageTag, with: makeDataSource(for: languageTag, content: newContent))
            } catch {
                logger?.logW(
                    source: self,
                    prefix: #function,
                    message: "Locale update failed [\(languageTag)] (\(url.absoluteString))",
                    cause: error
                )
                await suppressAfterError(for: languageTag, content: existingContent)
            }
        case .fail(let error):
            switch error {
            case .httpError(let http) where http.statusCode == 404:
                logger?.logW(
                    source: self,
                    prefix: #function,
                    message: "Locale 404 [\(languageTag)] (\(url.absoluteString)). Backing off for 1h"
                )
                let now = Date().timeIntervalSince1970
                let placeholder = ServerLocaleContent(languageTag: languageTag, content: nil, timeStamp: now, backoffUntil: now + 60 * 60)
                try? await dataStore.setContent(placeholder, for: languageTag)
                await onUpdateFinished(for: languageTag, with: nil)
            case .networkError:
                logger?.logW(
                    source: self,
                    prefix: #function,
                    message: "Locale data update failed [\(languageTag)] (\(url.absoluteString)) (\(error.description))"
                )
            case .httpError, .responseError:
                logger?.logW(
                    source: self,
                    prefix: #function,
                    message: "Locale data update failed [\(languageTag)] (\(url.absoluteString)) (\(error.description))"
                )
                await suppressAfterError(for: languageTag, content: existingContent)
            }
        }
    }

    /// Publishes a temporary fallback after a non-network refresh failure.
    private func suppressAfterError(for languageTag: LanguageTag, content: ServerLocaleContent?) async {
        let contentToSend = ServerLocaleContent(
            languageTag: languageTag,
            content: content?.content,
            timeStamp: Date().timeIntervalSince1970,
            backoffUntil: nil
        )
        try? await dataStore.setContent(contentToSend, for: languageTag)
        await onUpdateFinished(for: languageTag, with: makeDataSource(for: languageTag, content: contentToSend))
    }

    /// Emits the latest data source to active subscribers.
    private func onUpdateFinished(for languageTag: LanguageTag, with dataSource: (any ServerLocaleDataSource)?) async {
        await stateActor.updateCache(with: dataSource, for: languageTag)
        await stateActor.yield(dataSource, for: languageTag)
    }

    private func makeDataSource(for languageTag: LanguageTag, content: ServerLocaleContent) -> (any ServerLocaleDataSource)? {
        guard content.content != nil else { return nil }
        return ServerLocaleDataSourceImpl(languageTag: languageTag, content: content, logger: logger)
    }
}

extension ServerLocaleDataSourceProviderImpl {

    fileprivate final class WeakBox<T: AnyObject>: @unchecked Sendable {
        weak var value: T?
        init(_ value: T? = nil) { self.value = value }
    }

    fileprivate struct ServerLocaleDataSourceImpl: ServerLocaleDataSource {
        let languageTag: LanguageTag
        let content: ServerLocaleContent
        let logger: OwnIDLogRouter?

        func getString(key: String...) -> String? {
            let value = content.getString(localeKeys: key)
            guard value != nil else {
                logger?.logW(source: self, prefix: "getString", message: "Failed to get [\(languageTag)]@\(key) => value not found")
                return nil
            }
            return value
        }
    }

    private actor StateActor {
        private var continuations = [LanguageTag: [UUID: AsyncStream<(any ServerLocaleDataSource)?>.Continuation]]()
        private var updateTasks = [LanguageTag: Task<Void, Never>]()
        private var cachedDataSources = [LanguageTag: any ServerLocaleDataSource]()

        func updateCache(with dataSource: (any ServerLocaleDataSource)?, for languageTag: LanguageTag) {
            if let dataSource {
                cachedDataSources[languageTag] = dataSource
            } else {
                cachedDataSources.removeValue(forKey: languageTag)
            }
        }

        func register(
            _ continuation: AsyncStream<(any ServerLocaleDataSource)?>.Continuation,
            for languageTag: LanguageTag,
            id: UUID
        ) -> (any ServerLocaleDataSource)? {
            var tagContinuations = continuations[languageTag, default: [:]]
            tagContinuations[id] = continuation
            continuations[languageTag] = tagContinuations
            return cachedDataSources[languageTag]
        }

        func unregister(id: UUID, for languageTag: LanguageTag) {
            continuations[languageTag]?.removeValue(forKey: id)
            if continuations[languageTag]?.isEmpty == true {
                continuations.removeValue(forKey: languageTag)
            }
        }

        func yield(_ dataSource: (any ServerLocaleDataSource)?, for languageTag: LanguageTag) {
            guard let tagContinuations = continuations[languageTag] else { return }
            for continuation in tagContinuations.values {
                continuation.yield(dataSource)
            }
        }

        func reserveUpdate(for languageTag: LanguageTag) -> Bool {
            guard updateTasks[languageTag] == nil else { return false }
            updateTasks[languageTag] = Task {}
            return true
        }

        func record(_ task: Task<Void, Never>, for languageTag: LanguageTag) {
            updateTasks[languageTag] = task
        }

        func finishUpdate(for languageTag: LanguageTag) {
            updateTasks[languageTag] = nil
        }
    }
}
