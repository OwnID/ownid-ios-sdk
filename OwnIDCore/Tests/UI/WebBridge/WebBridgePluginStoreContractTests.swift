import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: WB-050, WB-060, WB-070, WB-080, WB-090, WB-130, WB-150, WB-160
struct WebBridgePluginStoreContractTests {

    @Test func `Plugin key canonicalizes case for equality hashing and description`() {
        let lowercase = WebBridgePluginKey(id: "storage")
        let uppercase = WebBridgePluginKey(id: "STORAGE")

        #expect(lowercase.id == "STORAGE")
        #expect(lowercase.key == "STORAGE")
        #expect(lowercase.description == "STORAGE")
        #expect(lowercase == uppercase)
        #expect(Set([lowercase, uppercase]).count == 1)
    }

    @Test func `Plugin default injection data uses key ID and skips empty actions`() throws {
        let exposed = WebBridgeFixturePlugin(id: "fido", actions: ["get", "create"])
        let hidden = WebBridgeFixturePlugin(id: "metadata", actions: [])

        try expectInjectionData(exposed, id: "FIDO", actions: ["get", "create"])
        #expect(hidden.injectionData() == nil)
    }

    @Test func `Built-in plugin keys expose stable namespaces and advertised actions`() {
        #expect(WebBridgeContextPluginImpl.KEY.id == "CONTEXT")
        #expect(webBridgePasskeyPluginKeyValue() == "FIDO")
        #expect(WebBridgeUserRepositoryPlugin.KEY.id == "STORAGE")
        #expect(WebBridgeSocialPlugin.KEY.id == "SOCIAL")
        #expect(WebBridgeMetadataPlugin.KEY.id == "METADATA")
        #expect(WebBridgeElitePlugin.KEY.id == "FLOW")

        let coder = JSONCoderImpl()
        let context = WebBridgeContextPluginImpl(context: nil)
        let storage = WebBridgeUserRepositoryPlugin(
            userRepository: WebBridgePluginMatrixUserRepository(),
            loginIdValidator: WebBridgePluginMatrixLoginIDValidator(),
            coder: coder
        )
        let metadata = WebBridgeMetadataPlugin(localInfo: WebBridgePluginMatrixLocalInfo(), coder: coder)

        #expect(context.actions == ["get"])
        #expect(storage.actions == ["setLastUser", "getLastUser"])
        #expect(metadata.actions == ["get"])

        if #available(iOS 16.0, *) {
            let passkey = WebBridgePasskeyPlugin(
                passkey: WebBridgePluginMatrixPasskey(),
                localInfo: WebBridgePluginMatrixLocalInfo(),
                coder: coder
            )

            #expect(passkey.key.id == "FIDO")
            #expect(passkey.actions == ["isAvailable", "create", "get"])
        }
    }

    @Test func `Built-in plugin injection data reflects pure capability matrix`() throws {
        let coder = JSONCoderImpl()
        let contextPlugin = WebBridgeContextPluginImpl(context: webBridgeContext())
        let storagePlugin = WebBridgeUserRepositoryPlugin(
            userRepository: WebBridgePluginMatrixUserRepository(),
            loginIdValidator: WebBridgePluginMatrixLoginIDValidator(),
            coder: coder
        )
        let metadataPlugin = WebBridgeMetadataPlugin(localInfo: WebBridgePluginMatrixLocalInfo(), coder: coder)
        let socialPlugin = WebBridgeSocialPlugin(
            signInWithApple: WebBridgePluginMatrixSignInWithApple(),
            signInWithGoogle: WebBridgePluginMatrixSignInWithGoogle(),
            coder: coder
        )
        let elitePlugin = WebBridgeElitePlugin(
            sessionCreate: nil,
            passwordAuthenticate: nil,
            loginIDValidator: WebBridgePluginMatrixLoginIDValidator(),
            coder: coder
        )
        elitePlugin.addEventWrappers([
            WebBridgePluginMatrixEventWrapper(action: "onNativeAction"),
            WebBridgePluginMatrixEventWrapper(action: "onFinish"),
        ])

        try expectInjectionData(contextPlugin, id: "CONTEXT", actions: ["get"])
        try expectInjectionData(storagePlugin, id: "STORAGE", actions: ["setLastUser", "getLastUser"])
        try expectInjectionData(metadataPlugin, id: "METADATA", actions: ["get"])
        try expectInjectionData(socialPlugin, id: "SOCIAL", actions: ["Apple", "Google"])
        try expectInjectionData(elitePlugin, id: "FLOW", actions: ["onNativeAction", "onFinish"])

        #expect(WebBridgeContextPluginImpl(context: nil).injectionData() == nil)
        #expect(WebBridgeSocialPlugin(signInWithApple: nil, signInWithGoogle: nil, coder: coder).injectionData() == nil)

        if #available(iOS 16.0, *) {
            let passkeyPlugin = WebBridgePasskeyPlugin(
                passkey: WebBridgePluginMatrixPasskey(),
                localInfo: WebBridgePluginMatrixLocalInfo(),
                coder: coder
            )

            try expectInjectionData(passkeyPlugin, id: "FIDO", actions: ["isAvailable", "create", "get"])
        }
    }

    @Test func `Default instance injection registers WebBridge built-in injection data`() throws {
        let container = try makeDefaultInjectedContainer()
        let defaultFactoryStore = try #require(container.getOrNil(type: WebBridgePluginFactoryStoreImpl.self))

        #expect(defaultFactoryStore.has(key: WebBridgeSocialPlugin.KEY))
        #expect(defaultFactoryStore.has(key: WebBridgeUserRepositoryPlugin.KEY))
        #expect(defaultFactoryStore.has(key: WebBridgeMetadataPlugin.KEY))
        #expect(defaultFactoryStore.has(key: WebBridgeContextPluginImpl.KEY))
        #expect(defaultFactoryStore.has(key: WebBridgeElitePlugin.KEY))

        var expectedPluginIDs = Set(["CONTEXT", "STORAGE", "METADATA", "SOCIAL", "FLOW"])
        if #available(iOS 16.0, *) {
            #expect(defaultFactoryStore.has(key: WebBridgePasskeyPlugin.KEY))
            expectedPluginIDs.insert("FIDO")
        }

        let scopedWebBridge = container.webBridgeNamespace
            .withContext("webbridge-default-context") { builder in
                builder.authz = .start("webbridge-default@example.test", type: .email)
                builder.accountDisplayName = "Default WebBridge User"
            }
            .withProviders("webbridge-default-google-provider") { registrar in
                registrar.signInWithGoogle { builder in
                    builder.signIn { _ in .success(id: "google-id", idToken: "google-id-token") }
                }
                registrar.sessionCreate { builder in
                    builder.create { _ in .success(SessionOutput(session: "session")) }
                }
                registrar.passwordAuthenticate { builder in
                    builder.authenticate { _ in .success(SessionOutput(session: "session")) }
                }
            }

        let injectionData = injectionDataByPluginID(scopedWebBridge.create())

        #expect(Set(injectionData.keys) == expectedPluginIDs)
        #expect(injectionData["CONTEXT"] == ["get"])
        #expect(injectionData["STORAGE"] == ["setLastUser", "getLastUser"])
        #expect(injectionData["METADATA"] == ["get"])
        #expect(injectionData["SOCIAL"] == ["Apple", "Google"])
        #expect(injectionData["FLOW"] == ["session_create", "auth_password_authenticate"])

        if #available(iOS 16.0, *) {
            #expect(injectionData["FIDO"] == ["isAvailable", "create", "get"])
        }
    }

    @Test(arguments: SocialPluginAvailabilityCase.all)
    func `Social plugin advertises only registered provider actions`(_ testCase: SocialPluginAvailabilityCase) throws {
        let plugin = testCase.makePlugin(coder: JSONCoderImpl())

        #expect(plugin.actions == testCase.actions)
        if testCase.actions.isEmpty {
            #expect(plugin.injectionData() == nil)
        } else {
            try expectInjectionData(plugin, id: "SOCIAL", actions: testCase.actions)
        }
    }

    @Test func `Elite plugin advertises provider and operation wrapper actions in registration order`() throws {
        let elite = WebBridgeElitePlugin(
            sessionCreate: WebBridgePluginMatrixSessionCreate(),
            passwordAuthenticate: WebBridgePluginMatrixPasswordAuthenticate(),
            loginIDValidator: WebBridgePluginMatrixLoginIDValidator(),
            coder: JSONCoderImpl()
        )

        try expectInjectionData(elite, id: "FLOW", actions: ["session_create", "auth_password_authenticate"])

        elite.addEventWrappers([
            WebBridgePluginMatrixEventWrapper(action: "onError"),
            WebBridgePluginMatrixEventWrapper(action: "onClose"),
        ])

        try expectInjectionData(
            elite,
            id: "FLOW",
            actions: ["session_create", "auth_password_authenticate", "onError", "onClose"]
        )
    }

    @Test func `Plugin registry replaces by key without moving existing slot`() throws {
        let originalStorage = WebBridgeFixturePlugin(id: "storage", marker: "original")
        let metadata = WebBridgeFixturePlugin(id: "metadata", marker: "metadata")
        let replacementStorage = WebBridgeFixturePlugin(id: "STORAGE", marker: "replacement")
        let social = WebBridgeFixturePlugin(id: "social", marker: "social")

        let registry = WebBridgePluginRegistryImpl(initialPlugins: [
            originalStorage,
            metadata,
            replacementStorage,
        ])

        #expect(try snapshotMarkers(registry) == ["replacement", "metadata"])
        let storedStorage = try #require(registry.get(key: WebBridgePluginKey(id: "storage")) as? WebBridgeFixturePlugin)
        #expect(storedStorage === replacementStorage)

        registry.add(plugin: social)
        registry.add(plugin: WebBridgeFixturePlugin(id: "metadata", marker: "metadata-replacement"))

        #expect(try snapshotMarkers(registry) == ["replacement", "metadata-replacement", "social"])

        registry.remove(key: WebBridgePluginKey(id: "STORAGE"))

        #expect(try snapshotMarkers(registry) == ["metadata-replacement", "social"])
        #expect(registry.get(key: WebBridgePluginKey(id: "storage")) == nil)
    }

    @Test func `Plugin factory store copies independently and instantiates current snapshot`() throws {
        let storageKey = WebBridgePluginKey(id: "storage")
        let metadataKey = WebBridgePluginKey(id: "metadata")
        let store = WebBridgePluginFactoryStoreImpl()

        store.register(key: storageKey) { WebBridgeFixturePlugin(id: "storage", marker: "storage-original") }
        store.register(key: metadataKey) { WebBridgeFixturePlugin(id: "metadata", marker: "metadata") }
        store.register(key: storageKey) { WebBridgeFixturePlugin(id: "STORAGE", marker: "storage-replacement") }

        let copiedStore = store.copyStore()
        store.unregister(key: metadataKey)

        #expect(store.has(key: storageKey))
        #expect(!store.has(key: metadataKey))
        #expect(copiedStore.has(key: storageKey))
        #expect(copiedStore.has(key: metadataKey))

        #expect(
            try pluginMarkers(copiedStore.instantiateAll(resolver: EmptyWebBridgeResolver())) == [
                "storage-replacement", "metadata",
            ]
        )
        #expect(try pluginMarkers(store.instantiateAll(resolver: EmptyWebBridgeResolver())) == ["storage-replacement"])
    }

    @Test func `Plugin factory store skips throwing and mismatched factories`() throws {
        let store = WebBridgePluginFactoryStoreImpl()
        let throwingKey = WebBridgePluginKey(id: "throwing")
        let mismatchedKey = WebBridgePluginKey(id: "expected")
        let validKey = WebBridgePluginKey(id: "valid")

        store.register(key: throwingKey) { throw WebBridgeFactoryError.expected }
        store.register(key: mismatchedKey) { WebBridgeFixturePlugin(id: "actual", marker: "mismatched") }
        store.register(key: validKey) { WebBridgeFixturePlugin(id: "valid", marker: "valid") }

        #expect(try pluginMarkers(store.instantiateAll(resolver: EmptyWebBridgeResolver())) == ["valid"])
    }

    @Test func `Namespace default factories affect future bridges only`() throws {
        let namespace = makeNamespace()

        registerFixture(in: namespace.defaultPluginFactories, id: "storage", marker: "first")
        let firstBridge = namespace.create()

        registerFixture(in: namespace.defaultPluginFactories, id: "storage", marker: "second")
        let secondBridge = namespace.create()

        #expect(try snapshotMarkers(firstBridge.plugins) == ["first"])
        #expect(try snapshotMarkers(secondBridge.plugins) == ["second"])
    }

    @Test func `Scoped namespace factory copies are isolated from later parent changes`() throws {
        let parent = makeNamespace()

        registerFixture(in: parent.defaultPluginFactories, id: "shared", marker: "parent-initial")

        let scoped = parent.withContext("webbridge-scoped-copy") { builder in
            builder.accountDisplayName = "Scoped User"
        }
        registerFixture(in: scoped.defaultPluginFactories, id: "scoped-only", marker: "scoped-only")

        registerFixture(in: parent.defaultPluginFactories, id: "shared", marker: "parent-updated")
        registerFixture(in: parent.defaultPluginFactories, id: "parent-only", marker: "parent-only")

        #expect(try snapshotMarkers(parent.create().plugins) == ["parent-updated", "parent-only"])
        #expect(try snapshotMarkers(scoped.create().plugins) == ["parent-initial", "scoped-only"])
    }

    @Test func `Bridge creation captures scoped context and providers through namespace factory resolver`() throws {
        let root = makeNamespace()
        let key = WebBridgePluginKey(id: "captured")
        let scoped = root
            .withContext("webbridge-captured-context") { builder in
                builder.authz = .start("scoped@example.test", type: .email)
            }
            .withProviders("webbridge-captured-providers") { registrar in
                registrar.sessionCreate { builder in
                    builder.create { _ in .success(SessionOutput(session: "ok")) }
                }
            }

        scoped.pluginFactoryStore.registerBuiltIn(key: key) { resolver in
            let context = resolver.getOrNil(type: Context.self)
            let sessionCreate = resolver.getOrNil(type: (any SessionCreate).self)
            return WebBridgeFixturePlugin(
                id: "captured",
                marker: "\(context?.loginID?.id ?? "missing-context"):\(sessionCreate == nil ? "missing-provider" : "provider")"
            )
        }

        #expect(try snapshotMarkers(root.create().plugins) == [])
        #expect(try snapshotMarkers(scoped.create().plugins) == ["scoped@example.test:provider"])
    }

    private func expectInjectionData(
        _ plugin: any WebBridgePlugin,
        id: String,
        actions: [String]
    ) throws {
        let injectionData = try #require(plugin.injectionData())
        #expect(injectionData.0 == id)
        #expect(injectionData.1 == actions)
    }

    private func snapshotMarkers(_ registry: any WebBridgePluginRegistry) throws -> [String] {
        try pluginMarkers(registry.snapshot())
    }

    private func pluginMarkers(_ plugins: [any WebBridgePlugin]) throws -> [String] {
        try plugins.map { plugin in
            try #require(plugin as? WebBridgeFixturePlugin).marker
        }
    }

    private func makeNamespace() -> OwnIDWebBridge {
        let container = DIContainerImpl(scopeName: "webbridge-plugin-store-namespace")
        container.register(WebBridgePluginFactoryStoreImpl.self, instance: WebBridgePluginFactoryStoreImpl())
        container.register((any JSONCoder).self, instance: JSONCoderImpl())
        container.register((any AppConfigProvider).self, instance: WebBridgePluginStoreAppConfigProvider())
        return container.webBridgeNamespace
    }

    private func makeDefaultInjectedContainer() throws -> DIContainerImpl {
        let container = DIContainerImpl(scopeName: "webbridge-default-injection")
        container.register((any JSONCoder).self, instance: JSONCoderImpl())
        container.injectInstanceDefaults(
            instanceName: InstanceName(value: "WB017Default"),
            configuration: try OwnIDConfigurationImpl(appID: "WB017Default")
        )
        container.register((any LocalInfo).self, instance: WebBridgePluginMatrixLocalInfo())
        container.register((any LanguageTagsProvider).self, instance: WebBridgePluginStoreLanguageTagsProvider())
        container.register((any AppConfigProvider).self, instance: WebBridgePluginStoreAppConfigProvider())
        return container
    }

    private func injectionDataByPluginID(_ bridge: any WebBridge) -> [String: [String]] {
        bridge.plugins.snapshot().reduce(into: [:]) { result, plugin in
            if let injectionData = plugin.injectionData() {
                result[injectionData.0] = injectionData.1
            }
        }
    }

    private func registerFixture(
        in store: any WebBridgePluginFactoryStore,
        id: String,
        marker: String
    ) {
        store.register(key: WebBridgePluginKey(id: id)) {
            WebBridgeFixturePlugin(id: id, marker: marker)
        }
    }
}

private final class WebBridgePluginStoreLanguageTagsProvider: LanguageTagsProvider, @unchecked Sendable {
    func setLanguageTags(_ tags: [String]) {}

    var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            continuation.yield([.default])
            continuation.finish()
        }
    }
}

struct SocialPluginAvailabilityCase: CustomStringConvertible, Sendable {
    let description: String
    let apple: Bool
    let google: Bool
    let actions: [String]

    func makePlugin(coder: any JSONCoder) -> WebBridgeSocialPlugin {
        WebBridgeSocialPlugin(
            signInWithApple: apple ? WebBridgePluginMatrixSignInWithApple() : nil,
            signInWithGoogle: google ? WebBridgePluginMatrixSignInWithGoogle() : nil,
            coder: coder
        )
    }

    static let all = [
        SocialPluginAvailabilityCase(description: "none", apple: false, google: false, actions: []),
        SocialPluginAvailabilityCase(description: "Apple", apple: true, google: false, actions: ["Apple"]),
        SocialPluginAvailabilityCase(description: "Google", apple: false, google: true, actions: ["Google"]),
        SocialPluginAvailabilityCase(description: "Apple and Google", apple: true, google: true, actions: ["Apple", "Google"]),
    ]
}

private func webBridgeContext() -> Context {
    var builder = Context.Builder()
    builder.authz = .start("webbridge@example.test", type: .email)
    builder.accountDisplayName = "WebBridge User"
    return builder.build(scopeName: "webbridge-plugin-store-tests")
}

private func webBridgePasskeyPluginKeyValue() -> String {
    if #available(iOS 16.0, *) {
        return WebBridgePasskeyPlugin.KEY.id
    }
    return "FIDO"
}

private final class WebBridgePluginStoreAppConfigProvider: AppConfigProvider, @unchecked Sendable {
    func getOrFetchConfig() async throws -> AppConfig {
        .default
    }

    var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
