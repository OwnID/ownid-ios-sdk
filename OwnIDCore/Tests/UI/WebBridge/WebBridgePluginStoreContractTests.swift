import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

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
