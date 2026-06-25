import Foundation

/// Main entry point for OwnID Core SDK instance lifecycle and namespace access.
///
/// Manages named SDK instances, exposes the default-instance namespaces through ``OwnID/flows``,
/// ``OwnID/headless``, and ``OwnID/webBridge``, and provides configuration helpers for logging, language tags, context,
/// and providers. This entry point is shipped by the `OwnIDCore` Swift Package product and `OwnIDCore` CocoaPods pod.
///
/// Initialize an instance from programmatic values, a JSON string, or a plist file before using instance-bound
/// namespaces. Successful initialization creates or replaces the named instance, stops work owned by the previous
/// same-name instance, and requires callers to reacquire instance and namespace handles. These entry-point calls are
/// synchronous and do not expose a cancellation callback. Configuration build failures are logged and leave the current
/// named instance unchanged.
///
/// Logging and explicit language tags are process-wide SDK settings. Configure logging before initialization when you
/// need startup or initial HTTP setup logs.
public enum OwnID: Sendable {

    /// Configures SDK-wide logging behavior.
    ///
    /// The most recent call replaces the previous logger. If you never call this, the SDK stays silent and uses a
    /// temporary ``OwnIDDefaultLogger`` only for configuration build failures.
    ///
    /// Configure logging before ``OwnID/initialize(instanceName:block:)``,
    /// ``OwnID/initializeFromJSON(instanceName:block:)``, or ``OwnID/initializeFromFile(instanceName:block:)`` if you
    /// need logs from configuration, instance creation, or initial HTTP setup.
    public static func logger(block: (OwnIDLoggerBuilder) -> Void) {
        OwnIDRootDIContainer.shared.register(OwnIDLoggerBuilder().apply(block).build() as any OwnIDLogger)
    }

    /// Creates or replaces an OwnID instance from programmatic configuration.
    ///
    /// A successful call installs SDK runtime services if needed, applies the optional language override from the builder,
    /// and creates the named instance. If an instance with the same name already exists, it is replaced and its
    /// instance-scoped work is stopped; fetch new ``OwnIDInstance`` and namespace handles after replacement.
    ///
    /// Invalid builders are logged and leave the current named instance unchanged.
    ///
    /// Example:
    ///
    /// ```swift
    /// OwnID.initialize { configuration in
    ///     configuration.appID = "<OWNID_APP_ID>"
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - instanceName: Logical name for the SDK instance; defaults to ``InstanceName/default``.
    ///   - block: Configures the instance via ``OwnIDConfigurationBuilder``.
    public static func initialize(instanceName: InstanceName = .default, block: (OwnIDConfigurationBuilder) -> Void) {
        let builder = OwnIDConfigurationBuilder().apply(block)
        initializeWithBuilder(instanceName: instanceName, buildName: "OwnID.initialize") {
            try builder.build()
        }
    }

    /// Creates or replaces an OwnID instance from JSON configuration.
    ///
    /// A successful call installs SDK runtime services if needed, applies the optional "languages" value from JSON, and
    /// creates the named instance. If an instance with the same name already exists, it is replaced and its
    /// instance-scoped work is stopped; fetch new ``OwnIDInstance`` and namespace handles after replacement.
    ///
    /// Invalid or malformed JSON is logged and leaves the current named instance unchanged.
    ///
    /// Example:
    ///
    /// ```swift
    /// OwnID.initializeFromJSON { configuration in
    ///     configuration.json = Bundle.main.object(forInfoDictionaryKey: "OwnIDConfigJSON") as? String ?? ""
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - instanceName: Logical name for the SDK instance; defaults to ``InstanceName/default``.
    ///   - block: Configures the instance via ``OwnIDJSONConfigurationBuilder``.
    public static func initializeFromJSON(instanceName: InstanceName = .default, block: (OwnIDJSONConfigurationBuilder) -> Void) {
        let builder = OwnIDJSONConfigurationBuilder().apply(block)
        initializeWithBuilder(instanceName: instanceName, buildName: "OwnID.initializeFromJSON") {
            try builder.build()
        }
    }

    /// Creates or replaces an OwnID instance from file configuration.
    ///
    /// The default file is `OwnIDConfig.plist` located in the main bundle. Missing, empty, unreadable, or invalid
    /// files are logged and leave the current named instance unchanged.
    ///
    /// A successful call installs SDK runtime services if needed, applies the optional "languages" value from the file, and
    /// creates the named instance. If an instance with the same name already exists, it is replaced and its
    /// instance-scoped work is stopped; fetch new ``OwnIDInstance`` and namespace handles after replacement.
    ///
    /// Example:
    ///
    /// ```swift
    /// OwnID.initializeFromFile { configuration in
    ///     configuration.fileURL = Bundle.main.url(forResource: "OwnIDConfig", withExtension: "plist")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - instanceName: Logical name for the SDK instance; defaults to ``InstanceName/default``.
    ///   - block: Configures the instance via ``OwnIDFileConfigurationBuilder``.
    public static func initializeFromFile(instanceName: InstanceName = .default, block: (OwnIDFileConfigurationBuilder) -> Void) {
        let builder = OwnIDFileConfigurationBuilder().apply(block)
        initializeWithBuilder(instanceName: instanceName, buildName: "OwnID.initializeFromFile") {
            try builder.build()
        }
    }

    /// Destroys the OwnID instance for `instanceName`.
    ///
    /// This call is idempotent: missing instances are ignored. Destroying an existing instance removes its SDK
    /// instance state and stops instance-scoped work.
    ///
    /// Previously returned ``OwnIDInstance`` handles and namespaces derived from them are invalid after this call.
    /// To continue working with the same logical instance name, fetch a new handle after reinitializing it.
    ///
    /// - Parameter instanceName: Logical name of the instance to destroy; defaults to ``InstanceName/default``.
    public static func destroy(instanceName: InstanceName = .default) {
        OwnIDRootDIContainer.shared.destroyInstanceContainer(instanceName)
    }

    /// Returns the current ``OwnIDInstance`` for the given name.
    ///
    /// The returned handle is bound to the current SDK instance scope for that name.
    /// If that named instance is later destroyed or reinitialized, fetch a new handle instead of reusing the old one.
    ///
    /// - Warning: Traps via `preconditionFailure` if the instance is missing.
    ///
    /// - Parameter instanceName: Logical name of the instance to fetch; defaults to ``InstanceName/default``.
    /// - Returns: The current instance.
    public static func instance(instanceName: InstanceName = .default) -> any OwnIDInstance {
        guard let instance = OwnIDRootDIContainer.shared.getInstanceNamespace(instanceName) else {
            preconditionFailure("No OwnID instance with name '\(instanceName.value)'")
        }
        return instance
    }

    /// Creates a child scope and registers a new ``Context`` in that scope.
    ///
    /// The child scope keeps the current scope's providers and configuration available.
    /// The returned handle stays bound to that child scope; it does not update the default instance in place.
    ///
    /// The ``Context`` registered in the child scope is built only from `block`.
    ///
    /// Requires an existing default instance; otherwise this call traps.
    ///
    /// - Parameters:
    ///   - scopeName: Name for the child scope; defaults to `"Context"`.
    ///   - block: Builder that sets context values (login ID or access token, and optionally `accountDisplayName`).
    /// - Returns: The scoped ``OwnIDInstance``.
    public static func withContext(_ scopeName: String = "Context", _ block: (inout Context.Builder) -> Void) -> any OwnIDInstance {
        instance().withContext(scopeName, block)
    }

    /// Updates the ``Context`` in the current scope in place.
    ///
    /// Unlike ``withContext(_:_:)``, this does not create a child scope.
    ///
    /// Requires an existing default instance; otherwise this call traps.
    ///
    /// Merge semantics:
    /// - Fields assigned in `block` replace existing values in the current scope.
    /// - Fields not assigned in `block` keep their existing values.
    /// - Assigning `nil` clears the field in the resulting context.
    ///
    /// - Parameter block: Builder that sets context values (login ID or access token, and optionally
    ///   `accountDisplayName`).
    /// - Returns: The updated ``OwnIDInstance``.
    @discardableResult
    public static func setContext(_ block: (inout Context.Builder) -> Void) -> any OwnIDInstance {
        instance().setContext(block)
    }

    /// Clears the ``Context`` from the default instance.
    ///
    /// This mutates the default instance scope in place and does not create a child scope. Clearing a missing
    /// ``Context`` is a no-op after the default instance has been created.
    ///
    /// Requires an existing default instance; otherwise this call traps.
    ///
    /// - Returns: The updated ``OwnIDInstance``.
    @discardableResult
    public static func clearContext() -> any OwnIDInstance {
        instance().clearContext()
    }

    /// Creates a child scope and registers providers from `block` in that scope.
    ///
    /// The child scope keeps the current scope's providers and configuration available.
    /// The returned handle stays bound to that child scope; it does not update the default instance in place.
    ///
    /// Providers declared in `block` replace providers of the same type only in that child scope.
    ///
    /// If `block` does not register any providers, returns the current instance unchanged.
    /// Providers and callbacks are owned by the app and stay available to SDK work that uses the returned scoped handle.
    ///
    /// Requires an existing default instance; otherwise this call traps.
    ///
    /// - Parameters:
    ///   - scopeName: Name for the child scope; defaults to `"Providers"`.
    ///   - block: Closure that registers providers via ``OwnIDProvidersRegistrar``.
    /// - Returns: The scoped ``OwnIDInstance``.
    public static func withProviders(
        _ scopeName: String = "Providers",
        _ block: (inout OwnIDProvidersRegistrar) -> Void
    ) -> any OwnIDInstance {
        instance().withProviders(scopeName, block)
    }

    /// Updates providers in the current scope in place.
    ///
    /// Unlike ``withProviders(_:_:)``, this does not create a child scope.
    ///
    /// Merge semantics:
    /// - Providers declared in `block` replace providers of the same type in the current scope.
    /// - Existing providers of supported types that are not declared in `block` remain unchanged.
    ///
    /// If `block` does not register any providers, returns the current instance unchanged.
    /// Registered providers replace same-type providers for SDK work that uses the current default instance after this
    /// call.
    ///
    /// Requires an existing default instance; otherwise this call traps.
    ///
    /// - Parameter block: Closure that registers providers via ``OwnIDProvidersRegistrar``.
    /// - Returns: The updated ``OwnIDInstance``.
    @discardableResult
    public static func setProviders(_ block: (inout OwnIDProvidersRegistrar) -> Void) -> any OwnIDInstance {
        instance().setProviders(block)
    }

    /// Sets the active language tags for the root SDK language provider.
    ///
    /// The provided tags replace system-based language detection globally for the current process.
    ///
    /// Passing an empty array restores system language tracking. Passing a non-empty array makes language tags update
    /// only through subsequent ``setLanguage(_:)`` calls until another empty array is passed or the process restarts.
    ///
    /// The root ``LanguageTagsProvider`` is installed during successful initialization. Calling this before
    /// initialization is a no-op; language tags supplied by initialization builders are applied during initialization.
    ///
    /// - Parameter tags: A list of BCP 47 language tags (e.g. `["en-US", "fr-FR"]`).
    public static func setLanguage(_ tags: [String]) {
        guard let provider = OwnIDRootDIContainer.shared.getOrNil(type: (any LanguageTagsProvider).self) else {
            return
        }
        provider.setLanguageTags(tags)
    }

    /// Returns ``OwnIDFlows`` for the default instance.
    ///
    /// The returned namespace is bound to the current default instance.
    /// Fetch it again after ``destroy(instanceName:)`` or same-name reinitialization instead of reusing the old handle.
    ///
    /// - Warning: Requires a created default instance; otherwise this call traps.
    public static var flows: OwnIDFlows {
        instance().flows
    }

    /// Returns ``OwnIDHeadless`` for the default instance.
    ///
    /// The returned namespace is bound to the current default instance.
    /// Fetch it again after ``destroy(instanceName:)`` or same-name reinitialization instead of reusing the old handle.
    ///
    /// - Warning: Requires a created default instance; otherwise this call traps.
    public static var headless: OwnIDHeadless {
        instance().headless
    }

    /// Returns ``OwnIDWebBridge`` for the default instance.
    ///
    /// Use this namespace to configure ``OwnIDWebBridge/defaultPluginFactories`` for future bridge instances or to
    /// create a fresh ``WebBridge`` for a web view session.
    ///
    /// The returned namespace is bound to the current default instance.
    /// Fetch it again after ``destroy(instanceName:)`` or same-name reinitialization instead of reusing the old handle.
    ///
    /// - Warning: Requires a created default instance; otherwise this call traps.
    public static var webBridge: OwnIDWebBridge {
        instance().webBridge
    }

    private static func initializeWithBuilder(
        instanceName: InstanceName,
        buildName: String,
        build: () throws -> (configuration: any OwnIDConfiguration, languages: [String]?)
    ) {
        let result: (configuration: any OwnIDConfiguration, languages: [String]?)
        do {
            result = try build()
        } catch {
            let logger = OwnIDRootDIContainer.shared.getOrNil(type: (any OwnIDLogger).self) ?? OwnIDDefaultLogger.make()
            logger.log(
                level: .error,
                className: buildName,
                message: "Configuration creation failed: \(error.localizedDescription)",
                cause: error
            )
            return
        }

        OwnIDRootDIContainer.shared.injectRootDefaults()
        if let languages = result.languages {
            OwnID.setLanguage(languages)
        }

        OwnIDRootDIContainer.shared.initializeInstanceContainer(instanceName, configuration: result.configuration)
    }

    /// Returns the current ``OwnIDInstance`` for the given name if it exists.
    ///
    /// This is an internal SDK module contract, not a public app integration contract.
    ///
    /// The returned handle is bound to the current SDK instance scope for that name.
    /// If that named instance is later destroyed or reinitialized, fetch a new handle instead of reusing the old one.
    ///
    /// - Parameter instanceName: Logical name of the instance to fetch; defaults to ``InstanceName/default``.
    /// - Returns: The current instance if present; otherwise `nil`.
    @_spi(OwnIDInternal)
    public static func instanceIfPresent(instanceName: InstanceName = .default) -> (any OwnIDInstance)? {
        OwnIDRootDIContainer.shared.getInstanceNamespace(instanceName)
    }

    /// Returns the internal DI container for the given instance name.
    ///
    /// This is an internal SDK module contract, not a public app integration contract. Use it for one-time access to SDK
    /// dependencies scoped to a named instance. The returned container is a lifecycle-bound view; do not keep it across
    /// instance replacement or destruction.
    @_spi(OwnIDInternal)
    public static func getInstanceContainer(_ instanceName: InstanceName = .default) -> (any DIContainer)? {
        OwnIDRootDIContainer.shared.getInstanceContainer(instanceName)
    }

    /// Returns a stream of current and future DI-container availability updates for the given instance name.
    ///
    /// This is an internal SDK module contract, not a public app integration contract. Use it when a module should
    /// rebind to instance creation, replacement, or destruction instead of keeping a stale container view from
    /// ``getInstanceContainer(_:)``. The stream yields `nil` while the instance is unavailable and the current
    /// container when it is available.
    @_spi(OwnIDInternal)
    public static func getInstanceContainerStream(_ instanceName: InstanceName = .default) -> AsyncStream<(any DIContainer)?> {
        OwnIDRootDIContainer.shared.getInstanceContainerStream(instanceName)
    }

    /// Returns the currently configured SDK-wide logger, or `nil` if logging was not configured.
    ///
    /// This is an internal SDK module contract, not a public app integration contract. Internal SDK code can use this
    /// for one-off logging in places where an instance-scoped log router is not available.
    @_spi(OwnIDInternal)
    public static func getLogger() -> (any OwnIDLogger)? {
        OwnIDRootDIContainer.shared.getOrNil(type: (any OwnIDLogger).self)
    }
}
