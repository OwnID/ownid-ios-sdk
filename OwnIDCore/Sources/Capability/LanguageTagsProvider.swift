import Foundation

/// Manages and observes the active language tags for the SDK.
///
/// The root provider is shared by SDK instances in the current process. It supplies normalized ``LanguageTag`` values
/// for locale-sensitive SDK behavior, including the `Accept-Language` header and UI strings.
///
/// Passing a non-empty array to ``setLanguageTags(_:)`` installs an explicit process-wide override. The provider stops
/// system language tracking and updates only through later ``setLanguageTags(_:)`` calls until an empty array restores
/// tracking. Duplicate resolved tags are removed, and ``LanguageTag/default`` is used when no usable tag can be
/// resolved.
public protocol LanguageTagsProvider: Capability, Sendable {
    /// Sets the active language tags, replacing or restoring system-based language detection.
    ///
    /// - Parameter tags: BCP 47 language tags (for example, `["en-US", "fr-FR"]`). An empty array restores system
    /// language tracking and immediately publishes the current system languages.
    func setLanguageTags(_ tags: [String])

    /// Emits the current list of ``LanguageTag``s.
    ///
    /// Each stream yields the latest value when subscribed. It updates on system language changes while automatic
    /// tracking is active and on ``setLanguageTags(_:)`` calls.
    var languageTags: AsyncStream<[LanguageTag]> { get }
}
