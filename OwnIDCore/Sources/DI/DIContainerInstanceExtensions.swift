import Foundation

@_spi(OwnIDInternal) extension DIContainerRegistrar where Self: DIContainerResolver {

    /// Registers all default SDK capabilities, APIs, operations, and flows into this instance container.
    ///
    /// This is an internal SDK module contract, not a public app integration contract. Core owns the baseline instance
    /// graph, ``ShutdownToken``, and ``TaskScope``. Long-lived services should spawn instance-owned work through that
    /// task scope or observe the shutdown token so ``OwnID/destroy(instanceName:)`` and same-name reinitialization can
    /// cancel instance-owned work.
    ///
    /// Optional modules may add or replace module-owned extension bindings in this container. Core remains the owner of
    /// the baseline runtime contracts.
    @_spi(OwnIDInternal) public func injectInstanceDefaults(instanceName: InstanceName, configuration: any OwnIDConfiguration) {
        register(InstanceName.self, instance: instanceName)

        register((any OwnIDConfiguration).self, instance: configuration)

        register(ShutdownToken.self, instance: ShutdownToken())

        registerFactory(dependencies: [ShutdownToken.self]) { resolver -> TaskScope in
            TaskScope(shutdownToken: try resolver.getOrThrow(type: ShutdownToken.self))
        }

        // Keep one Storage owner per backing file to avoid concurrent writes through separate stores.
        do {
            let starage = StorageImpl(
                suiteName: try getOrThrow(type: (any OwnIDConfiguration).self).storageFileName(),
                logger: getOrNil(type: OwnIDLogRouter.self)
            )
            register((any Storage).self, instance: starage)
        } catch {
            getOrNil(type: OwnIDLogRouter.self)?.logW(
                source: self,
                prefix: "injectInstanceDefaults",
                message: "Failed to create Storage: \(error.localizedDescription)",
                cause: error
            )
        }

        registerFactory(dependencies: [(any Storage).self, (any JSONCoder).self]) { resolver -> (any UserRepository) in
            UserRepositoryImpl(
                storage: try resolver.getOrThrow(type: (any Storage).self),
                coder: try resolver.getOrThrow(type: (any JSONCoder).self)
            )
        }

        register(
            (any LoginIDConfigurationProvider).self,
            instance: LoginIDConfigurationProviderImpl(initialConfiguration: LoginIDConfiguration.default)
        )

        registerFactory(dependencies: [(any LoginIDConfigurationProvider).self]) { resolver -> (any LoginIDValidator) in
            LoginIDValidatorImpl(
                loginIDConfigurationProvider: try resolver.getOrThrow(type: (any LoginIDConfigurationProvider).self)
            )
        }

        do {
            let localInfo = try getOrThrow(type: (any LocalInfo).self)
            let config = URLSessionConfiguration.default
            config.httpAdditionalHeaders = ["User-Agent": localInfo.userAgent]
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            register(URLSession.self, instance: URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil))
        } catch {
            getOrNil(type: OwnIDLogRouter.self)?.logW(
                source: self,
                prefix: "injectInstanceDefaults",
                message: "Failed to create URLSession: \(error.localizedDescription)",
                cause: error
            )
        }

        registerFactory { resolver -> NetworkRequest.RetryConfig in NetworkRequest.RetryConfig.default }

        registerFactory(
            dependencies: [URLSession.self, (any LocalInfo).self, (any LanguageTagsProvider).self, (any OwnIDConfiguration).self]
        ) { resolver -> any NetworkProtocol in
            // Http logging only logged locally, no logs send to server.
            // Http logging only works with manual log level setup before OwnID.initialize {...}, like:
            // OwnID.logger {
            //   $0.level = .verbose
            // }
            // Any server side logs level will not trigger Http logs as NetworkImpl is already created (unless DI was reset).
            let resolvedLogger = resolver.getOrNil(type: (any OwnIDLogger).self)

            return NetworkImpl(
                urlSession: try resolver.getOrThrow(type: URLSession.self),
                requestAdapters: NetworkRequest.AdapterChain(adapters: [
                    NetworkRequest.DefaultHeadersAdapter(
                        localInfo: try resolver.getOrThrow(type: (any LocalInfo).self),
                        languageTagsProvider: try resolver.getOrThrow(type: (any LanguageTagsProvider).self),
                        appURLHeaderValue: try resolver.getOrThrow(type: (any OwnIDConfiguration).self).appURLHeaderValue()
                    )
                ]),
                retryConfig: resolver.getOrNil(type: NetworkRequest.RetryConfig.self) ?? NetworkRequest.RetryConfig.default,
                httpLogger: (resolvedLogger?.isEnabled(.debug) == true) ? HTTPLogger(logger: resolvedLogger!) : nil
            )
        }

        if #available(iOS 16.0, *) {
            register(
                (any PasskeyDiagnostics).self,
                instance: PasskeyDiagnosticsImpl(
                    localInfo: (try? getOrThrow(type: (any LocalInfo).self)) ?? LocalInfoImpl(),
                    logger: getOrNil(type: OwnIDLogRouter.self)
                )
            )

            registerFactory { resolver -> any PasskeyProtocol in
                PasskeyImpl(
                    uiContextProvider: (try? resolver.getOrThrow(type: (any UIContextProvider).self)) ?? UIContextProviderImpl(),
                    logger: resolver.getOrNil(type: OwnIDLogRouter.self),
                    diagnosticsProvider: { resolver.getOrNil(type: (any PasskeyDiagnostics).self) }
                )
            }
        }

        registerFactory { resolver -> any SignInWithApple in
            SignInWithAppleImpl(
                uiContextProvider: (try? resolver.getOrThrow(type: (any UIContextProvider).self)) ?? UIContextProviderImpl(),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        }

        registerFactory(dependencies: [(any OwnIDConfiguration).self]) { resolver -> any APIBaseURL in
            APIBaseURLImpl.create(resolver: resolver)
        }

        registerFactory { resolver -> any APICallInterceptor in
            APICallPipelineInterceptor(
                interceptors: [
                    DefaultApiFailLoggingInterceptor(serverLoggerProvider: { resolver.getOrNil(type: ServerLogger.self) })
                ]
            )
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any PasskeyAttestationAPI in PasskeyAttestationAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any PasskeyAssertionAPI in PasskeyAssertionAPIImpl.create(resolver: resolver)
        }

        do {
            let appConfigProvider = AppConfigProviderImpl(
                apiBaseURL: try getOrThrow(type: (any APIBaseURL).self),
                localInfo: try getOrThrow(type: (any LocalInfo).self),
                languageTagsProvider: try getOrThrow(type: (any LanguageTagsProvider).self),
                coder: try getOrThrow(type: (any JSONCoder).self),
                configuration: try getOrThrow(type: (any OwnIDConfiguration).self),
                loginIdConfigurationProvider: getOrNil(type: (any LoginIDConfigurationProvider).self),
                taskScope: try getOrThrow(type: TaskScope.self),
                logger: getOrNil(type: OwnIDLogRouter.self),
                interceptor: getOrNil(type: (any APICallInterceptor).self)
            )
            register((any AppConfigProvider).self, instance: appConfigProvider)
        } catch {
            getOrNil(type: OwnIDLogRouter.self)?.logW(
                source: self,
                prefix: "injectInstanceDefaults",
                message: "Failed to create AppConfigProvider: \(error.localizedDescription)",
                cause: error
            )
        }

        do {
            let serverLogger = ServerLogger(
                instanceName: try getOrThrow(type: InstanceName.self),
                configuration: try getOrThrow(type: (any OwnIDConfiguration).self),
                localInfo: try getOrThrow(type: (any LocalInfo).self),
                appConfigProvider: try getOrThrow(type: (any AppConfigProvider).self),
                network: try getOrThrow(type: (any NetworkProtocol).self),
                coder: try getOrThrow(type: (any JSONCoder).self),
                taskScope: try getOrThrow(type: TaskScope.self),
                ownIdLogger: getOrNil(type: (any OwnIDLogger).self)  // OwnIDLogger intentionally
            )
            register(ServerLogger.self, instance: serverLogger)
        } catch {
            getOrNil(type: OwnIDLogRouter.self)?.logW(
                source: self,
                prefix: "injectInstanceDefaults",
                message: "Failed to create ServerLogger: \(error.localizedDescription)",
                cause: error
            )
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any EmailVerificationAPI in EmailVerificationAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any PhoneVerificationAPI in PhoneVerificationAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any PasskeyEnrollAPI in PasskeyEnrollAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any EmailEnrollAPI in EmailEnrollAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any PhoneEnrollAPI in PhoneEnrollAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any OIDCAPI in OIDCAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any DiscoverAPI in DiscoverAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any LoginAPI in LoginAPIImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any APIBaseURL).self, (any NetworkProtocol).self, (any JSONCoder).self]) {
            resolver -> any EventsAPI in EventsAPIImpl.create(resolver: resolver)
        }

        do {
            let serverLocaleDataSourceProvider = ServerLocaleDataSourceProviderImpl(
                configuration: try getOrThrow(type: (any OwnIDConfiguration).self),
                network: try getOrThrow(type: (any NetworkProtocol).self),
                languageTagsProvider: try getOrThrow(type: (any LanguageTagsProvider).self),
                jsonCoder: try getOrThrow(type: (any JSONCoder).self),
                taskScope: try getOrThrow(type: TaskScope.self),
                logger: getOrNil(type: OwnIDLogRouter.self)
            )
            register((any ServerLocaleDataSourceProvider).self, instance: serverLocaleDataSourceProvider)
        } catch {
            getOrNil(type: OwnIDLogRouter.self)?.logW(
                source: self,
                prefix: "injectInstanceDefaults",
                message: "Failed to create ServerLocaleDataSourceProvider: \(error.localizedDescription)",
                cause: error
            )
        }

        registerFactory { _ -> any ErrorStringsEmbeddedRepository in ErrorStringsEmbeddedRepositoryImpl() }

        registerFactory(dependencies: [(any ServerLocaleDataSourceProvider).self]) { resolver -> any ErrorStringsServerRepository in
            do {
                return ErrorStringsServerRepositoryImpl(
                    serverLocaleProvider: try resolver.getOrThrow(type: (any ServerLocaleDataSourceProvider).self)
                )
            } catch { return ErrorStringsServerRepositoryEmptyFallback() }
        }

        registerFactory(
            dependencies: [
                (any LanguageTagsProvider).self,
                (any ErrorStringsEmbeddedRepository).self,
                (any ErrorStringsServerRepository).self,
                TaskScope.self,
            ]
        ) { resolver -> any ErrorStringsProvider in
            do {
                return ErrorStringsProviderImpl(
                    languageTagsProvider: try resolver.getOrThrow(type: (any LanguageTagsProvider).self),
                    embeddedRepository: try resolver.getOrThrow(type: (any ErrorStringsEmbeddedRepository).self),
                    serverRepository: try resolver.getOrThrow(type: (any ErrorStringsServerRepository).self),
                    taskScope: try resolver.getOrThrow(type: TaskScope.self)
                )
            } catch {
                let embeddedRepository =
                    resolver.getOrNil(type: (any ErrorStringsEmbeddedRepository).self) ?? ErrorStringsEmbeddedRepositoryImpl()
                return EmbeddedOnlyStringsProviderAdapter<ErrorStrings, ErrorStringsParams> { params in
                    embeddedRepository.fallbackToEmbedded(params: params, map: [:])
                }
            }
        }

        do {
            let resolver = ErrorStringsResolver(
                errorStringsProvider: getOrNil(type: (any ErrorStringsProvider).self),
                taskScope: try getOrThrow(type: TaskScope.self)
            )
            register(ErrorStringsResolver.self, instance: resolver)
        } catch {
            getOrNil(type: OwnIDLogRouter.self)?.logW(
                source: Self.self,
                prefix: "injectInstanceDefaults",
                message: "Failed to create ErrorStringsResolver: \(error.localizedDescription)",
                cause: error
            )
        }

        register((any OperationRegistry).self, instance: OperationRegistryImpl(logger: getOrNil(type: OwnIDLogRouter.self)))

        registerFactory(dependencies: [(any LocalInfo).self]) { resolver -> any LoginIDCollectStringsEmbeddedRepository in
            LoginIDCollectStringsEmbeddedRepositoryImpl(
                localInfo: resolver.getOrNil(type: (any LocalInfo).self)
            )
        }

        registerFactory(dependencies: [(any LocalInfo).self, (any ServerLocaleDataSourceProvider).self]) {
            resolver -> any LoginIDCollectStringsServerRepository in
            do {
                return LoginIDCollectStringsServerRepositoryImpl(
                    localInfo: try resolver.getOrThrow(type: (any LocalInfo).self),
                    serverLocaleProvider: try resolver.getOrThrow(type: (any ServerLocaleDataSourceProvider).self)
                )
            } catch { return LoginIDCollectStringsServerRepositoryEmptyFallback() }

        }

        registerFactory(
            dependencies: [
                (any LanguageTagsProvider).self,
                (any LoginIDCollectStringsEmbeddedRepository).self,
                (any LoginIDCollectStringsServerRepository).self,
                TaskScope.self,
            ]
        ) { resolver -> any LoginIDCollectStringsProvider in
            do {
                return LoginIDCollectStringsProviderImpl(
                    languageTagsProvider: try resolver.getOrThrow(type: (any LanguageTagsProvider).self),
                    embeddedRepository: try resolver.getOrThrow(type: (any LoginIDCollectStringsEmbeddedRepository).self),
                    serverRepository: try resolver.getOrThrow(type: (any LoginIDCollectStringsServerRepository).self),
                    taskScope: try resolver.getOrThrow(type: TaskScope.self)
                )
            } catch {
                let embeddedRepository =
                    resolver.getOrNil(type: (any LoginIDCollectStringsEmbeddedRepository).self)
                    ?? LoginIDCollectStringsEmbeddedRepositoryImpl(localInfo: resolver.getOrNil(type: (any LocalInfo).self))

                return EmbeddedOnlyStringsProviderAdapter<LoginIDCollectStrings, LoginIDCollectStringsParams> { params in
                    embeddedRepository.fallbackToEmbedded(params: params, map: [:])
                }
            }
        }

        registerFactory { _ -> any LoginIDCollectUI in NoopLoginIDCollectUI() }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any LoginIDCollectUI).self,
                (any LoginIDConfigurationProvider).self,
                (any LoginIDValidator).self,
                TaskScope.self,
            ]
        ) { resolver -> any LoginIDCollectOperation in LoginIDCollectOperationImpl.create(resolver: resolver) }

        registerFactory { _ -> any EmailVerificationStringsEmbeddedRepository in EmailVerificationStringsEmbeddedRepositoryImpl() }

        registerFactory(dependencies: [(any ServerLocaleDataSourceProvider).self]) {
            resolver -> any EmailVerificationStringsServerRepository in
            do {
                return EmailVerificationStringsServerRepositoryImpl(
                    serverLocaleProvider: try resolver.getOrThrow(type: (any ServerLocaleDataSourceProvider).self)
                )
            } catch { return EmailVerificationStringsServerRepositoryEmptyFallback() }
        }

        registerFactory(
            dependencies: [
                (any LanguageTagsProvider).self,
                (any EmailVerificationStringsEmbeddedRepository).self,
                (any EmailVerificationStringsServerRepository).self,
                TaskScope.self,
            ]
        ) { resolver -> any EmailVerificationStringsProvider in
            do {
                return EmailVerificationStringsProviderImpl(
                    languageTagsProvider: try resolver.getOrThrow(type: (any LanguageTagsProvider).self),
                    embeddedRepository: try resolver.getOrThrow(type: (any EmailVerificationStringsEmbeddedRepository).self),
                    serverRepository: try resolver.getOrThrow(type: (any EmailVerificationStringsServerRepository).self),
                    taskScope: try resolver.getOrThrow(type: TaskScope.self)
                )
            } catch {
                let embeddedRepository =
                    resolver.getOrNil(type: (any EmailVerificationStringsEmbeddedRepository).self)
                    ?? EmailVerificationStringsEmbeddedRepositoryImpl()

                return EmbeddedOnlyStringsProviderAdapter<EmailVerificationStrings, EmailVerificationStringsParams> { params in
                    embeddedRepository.fallbackToEmbedded(params: params, map: [:])
                }
            }
        }

        registerFactory { _ -> any EmailVerificationUI in NoopEmailVerificationUI() }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any EmailVerificationUI).self,
                (any EmailVerificationAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any EmailVerificationOperation in EmailVerificationOperationImpl.create(resolver: resolver) }

        registerFactory { _ -> any PhoneVerificationStringsEmbeddedRepository in PhoneVerificationStringsEmbeddedRepositoryImpl() }

        registerFactory(dependencies: [(any ServerLocaleDataSourceProvider).self]) {
            resolver -> any PhoneVerificationStringsServerRepository in
            do {
                return PhoneVerificationStringsServerRepositoryImpl(
                    serverLocaleProvider: try resolver.getOrThrow(type: (any ServerLocaleDataSourceProvider).self)
                )
            } catch { return PhoneVerificationStringsServerRepositoryEmptyFallback() }
        }

        registerFactory(
            dependencies: [
                (any LanguageTagsProvider).self,
                (any PhoneVerificationStringsEmbeddedRepository).self,
                (any PhoneVerificationStringsServerRepository).self,
                TaskScope.self,
            ]
        ) { resolver -> any PhoneVerificationStringsProvider in
            do {
                return PhoneVerificationStringsImpl(
                    languageTagsProvider: try resolver.getOrThrow(type: (any LanguageTagsProvider).self),
                    embeddedRepository: try resolver.getOrThrow(type: (any PhoneVerificationStringsEmbeddedRepository).self),
                    serverRepository: try resolver.getOrThrow(type: (any PhoneVerificationStringsServerRepository).self),
                    taskScope: try resolver.getOrThrow(type: TaskScope.self)
                )
            } catch {
                let embeddedRepository =
                    resolver.getOrNil(type: (any PhoneVerificationStringsEmbeddedRepository).self)
                    ?? PhoneVerificationStringsEmbeddedRepositoryImpl()

                return EmbeddedOnlyStringsProviderAdapter<PhoneVerificationStrings, PhoneVerificationStringsParams> { params in
                    embeddedRepository.fallbackToEmbedded(params: params, map: [:])
                }
            }
        }

        registerFactory { _ -> any PhoneVerificationUI in NoopPhoneVerificationUI() }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any PhoneVerificationUI).self,
                (any PhoneVerificationAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any PhoneVerificationOperation in PhoneVerificationOperationImpl.create(resolver: resolver) }

        registerFactory(dependencies: [(any PasskeyProtocol).self]) { resolver -> any PasskeyAttestationUI in
            PasskeyAttestationUIImpl(
                passkeyProvider: { try resolver.getOrThrow(type: (any PasskeyProtocol).self) }
            )
        }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any PasskeyAttestationUI).self,
                (any PasskeyAttestationAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any PasskeyAttestationOperation in PasskeyAttestationOperationImpl.create(resolver: resolver) }

        registerFactory(dependencies: [(any PasskeyProtocol).self]) { resolver -> any PasskeyAssertionUI in
            PasskeyAssertionUIImpl(
                passkeyProvider: { try resolver.getOrThrow(type: (any PasskeyProtocol).self) }
            )
        }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any PasskeyAssertionUI).self,
                (any PasskeyAssertionAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any PasskeyAssertionOperation in PasskeyAssertionOperationImpl.create(resolver: resolver) }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any PasskeyEnrollAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any PasskeyEnrollOperation in PasskeyEnrollOperationImpl.create(resolver: resolver) }

        registerFactory(dependencies: [(any SignInWithApple).self]) { resolver -> any SignInWithAppleUI in
            SignInWithAppleUIImpl(provider: { try resolver.getOrThrow(type: (any SignInWithApple).self) })
        }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any SignInWithAppleUI).self,
                (any OIDCAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any SignInWithAppleOperation in SignInWithAppleOperationImpl.create(resolver: resolver) }

        registerFactory(dependencies: [(any SignInWithGoogle).self]) { resolver -> any SignInWithGoogleUI in
            SignInWithGoogleUIImpl(provider: { try resolver.getOrThrow(type: (any SignInWithGoogle).self) })
        }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any SignInWithGoogleUI).self,
                (any OIDCAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any SignInWithGoogleOperation in SignInWithGoogleOperationImpl.create(resolver: resolver) }

        registerFactory(
            dependencies: [
                (any OperationRegistry).self,
                (any LoginIDValidator).self,
                (any LoginAPI).self,
                (any DiscoverAPI).self,
                TaskScope.self,
            ]
        ) { resolver -> any LoginOperation in
            LoginOperationImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [(any UIContextProvider).self]) { resolver -> any WebBridgePresenter in
            WebBridgePresenterImpl(
                uiContextProvider: try resolver.getOrThrow(type: (any UIContextProvider).self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        }

        registerFactory(dependencies: [(any WebBridgePresenter).self]) { resolver -> any WebBridgeUI in
            WebBridgeUIImpl(presenter: try resolver.getOrThrow(type: (any WebBridgePresenter).self))
        }

        registerFactory(dependencies: [
            (any OperationRegistry).self,
            (any OwnIDConfiguration).self,
            (any AppConfigProvider).self,
            (any LocalInfo).self,
            (any WebBridgeUI).self,
            (any WebBridge).self,
            TaskScope.self,
        ]) {
            resolver -> any WebBridgeOperation in WebBridgeOperationImpl.create(resolver: resolver)
        }

        registerFactory { _ -> any BoostWidgetStringsEmbeddedRepository in BoostWidgetStringsEmbeddedRepositoryImpl() }

        registerFactory(dependencies: [(any ServerLocaleDataSourceProvider).self]) { resolver -> any BoostWidgetStringsServerRepository in
            do {
                return BoostWidgetStringsServerRepositoryImpl(
                    serverLocaleProvider: try resolver.getOrThrow(type: (any ServerLocaleDataSourceProvider).self)
                )
            } catch { return BoostWidgetStringsServerRepositoryEmptyFallback() }
        }

        registerFactory(
            dependencies: [
                (any LanguageTagsProvider).self,
                (any BoostWidgetStringsEmbeddedRepository).self,
                (any BoostWidgetStringsServerRepository).self,
                TaskScope.self,
            ]
        ) { resolver -> any BoostWidgetStringsProvider in
            do {
                return WidgetStringsProviderImpl(
                    languageTagsProvider: try resolver.getOrThrow(type: (any LanguageTagsProvider).self),
                    embeddedRepository: try resolver.getOrThrow(type: (any BoostWidgetStringsEmbeddedRepository).self),
                    serverRepository: try resolver.getOrThrow(type: (any BoostWidgetStringsServerRepository).self),
                    taskScope: try resolver.getOrThrow(type: TaskScope.self)
                )
            } catch {
                let embeddedRepository =
                    resolver.getOrNil(type: (any BoostWidgetStringsEmbeddedRepository).self)
                    ?? BoostWidgetStringsEmbeddedRepositoryImpl()
                return EmbeddedOnlyStringsProviderAdapter<BoostWidgetStrings, BoostWidgetStringsParams> { params in
                    embeddedRepository.fallbackToEmbedded(params: params, map: [:])
                }
            }
        }
        let webBridgePluginFactoryStore = WebBridgePluginFactoryStoreImpl()
        register(webBridgePluginFactoryStore)

        registerFactory(dependencies: [(any JSONCoder).self]) { resolver in
            try WebBridgeSocialPlugin.create(resolver: resolver)
        }
        webBridgePluginFactoryStore.registerBuiltIn(key: WebBridgeSocialPlugin.KEY) { resolver in
            try resolver.getOrThrow(type: WebBridgeSocialPlugin.self)
        }

        registerFactory(dependencies: [(any UserRepository).self, (any LoginIDValidator).self, (any JSONCoder).self]) { resolver in
            try WebBridgeUserRepositoryPlugin.create(resolver: resolver)
        }
        webBridgePluginFactoryStore.registerBuiltIn(key: WebBridgeUserRepositoryPlugin.KEY) { resolver in
            try resolver.getOrThrow(type: WebBridgeUserRepositoryPlugin.self)
        }

        registerFactory(dependencies: [(any LocalInfo).self, (any JSONCoder).self]) { resolver in
            try WebBridgeMetadataPlugin.create(resolver: resolver)
        }
        webBridgePluginFactoryStore.registerBuiltIn(key: WebBridgeMetadataPlugin.KEY) { resolver in
            try resolver.getOrThrow(type: WebBridgeMetadataPlugin.self)
        }

        registerFactory { resolver -> any WebBridgeContextPlugin in
            try WebBridgeContextPluginImpl.create(resolver: resolver)
        }
        webBridgePluginFactoryStore.registerBuiltIn(key: WebBridgeContextPluginImpl.KEY) { resolver in
            try resolver.getOrThrow(type: WebBridgeContextPlugin.self)
        }

        if #available(iOS 16.0, *) {
            registerFactory(dependencies: [(any PasskeyProtocol).self, (any LocalInfo).self, (any JSONCoder).self]) { resolver in
                try WebBridgePasskeyPlugin.create(resolver: resolver)
            }
            webBridgePluginFactoryStore.registerBuiltIn(key: WebBridgePasskeyPlugin.KEY) { resolver in
                try resolver.getOrThrow(type: WebBridgePasskeyPlugin.self)
            }
        }

        registerFactory(dependencies: [(any JSONCoder).self, (any LoginIDValidator).self]) { resolver in
            try WebBridgeElitePlugin.create(resolver: resolver)
        }
        webBridgePluginFactoryStore.registerBuiltIn(key: WebBridgeElitePlugin.KEY) { resolver in
            try resolver.getOrThrow(type: WebBridgeElitePlugin.self)
        }

        registerFactory(
            dependencies: [WebBridgePluginFactoryStoreImpl.self, (any AppConfigProvider).self, (any JSONCoder).self]
        ) { resolver -> any WebBridge in
            WebBridgeImpl.create(
                resolver: resolver,
                initialPlugins: try resolver.getOrThrow(type: WebBridgePluginFactoryStoreImpl.self).instantiateAll(resolver: resolver)
            )
        }

        registerFactory(
            dependencies: [(any EventsAPI).self, (any LocalInfo).self, TaskScope.self]
        ) {
            resolver -> any UserJourney in UserJourneyImpl.create(resolver: resolver)
        }

        registerFactory(
            dependencies: [(any JSONCoder).self, (any LoginIDValidator).self, TaskScope.self]
        ) {
            resolver -> any BoostLoginFlow in BoostLoginFlowImpl.create(resolver: resolver)
        }

        registerFactory(
            dependencies: [(any BoostLoginFlow).self, (any JSONCoder).self, (any LoginIDValidator).self, TaskScope.self]
        ) {
            resolver -> any BoostCreatePasskeyFlow in BoostCreatePasskeyFlowImpl.create(resolver: resolver)
        }

        registerFactory(dependencies: [TaskScope.self]) {
            resolver -> any EliteFlow in EliteFlowImpl.create(resolver: resolver)
        }

        registerFactory(
            dependencies: [(any JSONCoder).self, (any LoginIDValidator).self, TaskScope.self]
        ) {
            resolver -> any PasskeyEnrollFlow in PasskeyEnrollFlowImpl.create(resolver: resolver)
        }

        // Optional modules may replace module-owned extension bindings while Core keeps ownership of baseline runtime contracts.
        OwnIDModuleInjector.injectIntoInstanceContainer(container: self)
    }
}
