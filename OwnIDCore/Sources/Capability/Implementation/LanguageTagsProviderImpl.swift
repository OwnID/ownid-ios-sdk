import Foundation

/// Root ``LanguageTagsProvider`` backed by `Locale.preferredLanguages` and locale-change notifications.
///
/// The provider publishes system languages while automatic tracking is active. A non-empty override stops system
/// tracking until an empty override restores it. Streams yield the current value when subscribed.
internal final class LanguageTagsProviderImpl: LanguageTagsProvider, @unchecked Sendable {
    private typealias TagsContinuation = AsyncStream<[LanguageTag]>.Continuation
    private typealias TagsUpdate = ([LanguageTag], [TagsContinuation])

    // @unchecked Sendable: mutable state is serialized internally.
    private let stateQueue = DispatchQueue(label: "com.ownid.language-tags-provider.state")
    private let stateQueueKey = DispatchSpecificKey<Void>()

    private let logger: OwnIDLogRouter?
    private var isObservingSystemChanges = true
    private var currentTags: [LanguageTag]
    private var continuations: [UUID: TagsContinuation] = [:]
    private var notificationToken: NSObjectProtocol?

    internal var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                self?.stateQueue.async { [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
            let initialTags = onStateQueueSync {
                continuations[id] = continuation
                return currentTags
            }
            continuation.yield(initialTags)
        }
    }

    init(logger: OwnIDLogRouter?) {
        self.logger = logger
        self.currentTags = Self.extractSystemLanguageTags()
        stateQueue.setSpecific(key: stateQueueKey, value: ())

        logger?.logD(source: self, prefix: "init", message: "Application languages: \(currentTags)")

        onStateQueueSync {
            _ = startObservingSystemChangesOnQueue()
        }
    }

    deinit {
        let (token, continuationsToFinish): (NSObjectProtocol?, [TagsContinuation]) = onStateQueueSync {
            let token = notificationToken
            notificationToken = nil
            isObservingSystemChanges = false
            let continuationsToFinish = Array(continuations.values)
            continuations.removeAll()
            return (token, continuationsToFinish)
        }

        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        for continuation in continuationsToFinish {
            continuation.finish()
        }
    }

    func setLanguageTags(_ tags: [String]) {
        if tags.isEmpty {
            resetToSystemLanguageTags()
            return
        }

        let resolvedTags = Self.resolveLanguageTags(tags)

        let (tokenToRemove, update): (NSObjectProtocol?, TagsUpdate?) = onStateQueueSync {
            let tokenToRemove = stopObservingSystemChangesOnQueue()

            guard resolvedTags != currentTags else {
                return (tokenToRemove, nil)
            }
            currentTags = resolvedTags
            return (tokenToRemove, (resolvedTags, Array(continuations.values)))
        }

        if let tokenToRemove {
            NotificationCenter.default.removeObserver(tokenToRemove)
            logger?.logD(source: self, prefix: "setLanguageTags", message: "Stopped observing system changes.")
        }

        publish(update, prefix: "setLanguageTags")
    }

    private func resetToSystemLanguageTags() {
        let update: TagsUpdate? = onStateQueueSync {
            _ = startObservingSystemChangesOnQueue()
            let resolvedTags = Self.extractSystemLanguageTags()

            guard resolvedTags != currentTags else {
                return nil
            }
            currentTags = resolvedTags
            return (resolvedTags, Array(continuations.values))
        }

        publish(update, prefix: "setLanguageTags")
    }

    private func startObservingSystemChangesOnQueue() -> Bool {
        guard !isObservingSystemChanges || notificationToken == nil else {
            return false
        }

        isObservingSystemChanges = true
        if notificationToken == nil {
            notificationToken = NotificationCenter.default.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification,
                object: nil,
                queue: nil
            ) {
                [weak self] _ in
                self?.onSystemLocaleChanged()
            }
        }
        return true
    }

    private func stopObservingSystemChangesOnQueue() -> NSObjectProtocol? {
        guard isObservingSystemChanges else {
            return nil
        }

        isObservingSystemChanges = false
        let token = notificationToken
        notificationToken = nil
        return token
    }

    private func onSystemLocaleChanged() {
        let update: TagsUpdate? = onStateQueueSync {
            handleSystemLocaleChangedOnQueue()
        }

        publish(update, prefix: "onSystemLocaleChanged")
    }

    private func handleSystemLocaleChangedOnQueue() -> TagsUpdate? {
        guard isObservingSystemChanges else {
            return nil
        }
        let newTags = Self.extractSystemLanguageTags()
        guard newTags != currentTags else {
            return nil
        }
        currentTags = newTags
        return (newTags, Array(continuations.values))
    }

    private func publish(_ update: TagsUpdate?, prefix: String) {
        guard let (tags, continuationsToYield) = update else {
            return
        }
        for continuation in continuationsToYield {
            continuation.yield(tags)
        }
        logger?.logD(source: self, prefix: prefix, message: "Languages: \(tags)")
    }

    private func onStateQueueSync<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            return work()
        }
        return stateQueue.sync(execute: work)
    }

    private static func resolveLanguageTags(_ tags: [String]) -> [LanguageTag] {
        let resolved = tags.map { Locale(identifier: $0) }.map(LanguageTag.from(locale:)).removingDuplicates()
        return resolved.isEmpty ? [LanguageTag.default] : resolved
    }

    private static func extractSystemLanguageTags() -> [LanguageTag] {
        resolveLanguageTags(Locale.preferredLanguages)
    }
}

extension Array where Element: Hashable {
    fileprivate func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
