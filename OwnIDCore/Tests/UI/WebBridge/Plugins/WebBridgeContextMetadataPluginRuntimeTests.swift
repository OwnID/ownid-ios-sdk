import Foundation
import Testing

@testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct WebBridgeContextMetadataPluginRuntimeTests {
    private let coder = WebBridgeTestJSONCoder()

    @Test func `Context plugin returns login ID and display name payload`() async throws {
        var builder = Context.Builder()
        builder.authz = .start(LoginID(id: "webbridge@example.test", type: .email))
        builder.accountDisplayName = "WebBridge User"
        let plugin = WebBridgeContextPluginImpl(context: builder.build(scopeName: "webbridge-context-tests"))

        let result = await handleWebBridgePlugin(plugin, pluginID: "context", action: "get")
        let success = try #require(result.success)

        #expect(success["authz"]?["loginId"] == .string("webbridge@example.test"))
        #expect(success["authz"]?["accessToken"] == nil)
        #expect(success["accountDisplayName"] == .string("WebBridge User"))
    }

    @Test func `Context plugin returns access token payload`() async throws {
        var builder = Context.Builder()
        builder.authz = .fromToken("access-token-value")
        let plugin = WebBridgeContextPluginImpl(context: builder.build(scopeName: "webbridge-context-tests"))

        let result = await handleWebBridgePlugin(plugin, pluginID: "CONTEXT", action: "GET")
        let success = try #require(result.success)

        #expect(success["authz"]?["accessToken"] == .string("access-token-value"))
        #expect(success["authz"]?["loginId"] == nil)
    }

    @Test func `Context plugin without scoped context hides injection and returns unavailable error`() async throws {
        let plugin = WebBridgeContextPluginImpl(context: nil)

        #expect(plugin.injectionData() == nil)

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "CONTEXT",
            action: "get",
            coder: coder
        )

        #expect(error["message"]?.stringValue?.contains("Context is unavailable") == true)
        #expect(error["type"] == .string("UNKNOWN"))
    }

    @Test func `Metadata plugin returns correlation ID payload`() async throws {
        let plugin = WebBridgeMetadataPlugin(
            localInfo: WebBridgeRuntimePluginLocalInfo(correlationId: "correlation-metadata-test"),
            coder: coder
        )

        let result = await handleWebBridgePlugin(plugin, pluginID: "metadata", action: "get")

        #expect(result.success?["correlationId"] == .string("correlation-metadata-test"))
        #expect(result.error == nil)
    }

    @Test func `Metadata plugin maps unknown action to bridge error`() async throws {
        let plugin = WebBridgeMetadataPlugin(
            localInfo: WebBridgeRuntimePluginLocalInfo(correlationId: "correlation-metadata-test"),
            coder: coder
        )

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "METADATA",
            action: "missing",
            coder: coder
        )

        #expect(error["message"]?.stringValue?.contains("Unknown action: missing") == true)
        #expect(error["type"] == .string("UNKNOWN"))
    }
}
