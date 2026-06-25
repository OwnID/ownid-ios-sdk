import Foundation
import Testing

@testable import OwnIDCore

struct WebBridgePayloadResultContractTests {
    private let coder = WebBridgeTestJSONCoder()

    @Test func `Plugin message payload uses stable wire keys`() throws {
        let payload = WebBridgePluginMessage.Payload(
            pluginID: "FIDO",
            action: "create",
            callbackPath: "OwnID.native.callback",
            params: #"{"challenge":"abc"}"#
        )

        let encoded = try coder.encodeToJSONValue(payload)

        #expect(encoded["pluginId"] == .string("FIDO"))
        #expect(encoded["pluginID"] == nil)
        #expect(encoded["action"] == .string("create"))
        #expect(encoded["callbackPath"] == .string("OwnID.native.callback"))
        #expect(encoded["params"] == .string(#"{"challenge":"abc"}"#))

        let decoded = try coder.decodeFromJSONValue(encoded, as: WebBridgePluginMessage.Payload.self)

        #expect(decoded.pluginID == "FIDO")
        #expect(decoded.action == "create")
        #expect(decoded.callbackPath == "OwnID.native.callback")
        #expect(decoded.params == #"{"challenge":"abc"}"#)
    }

    @Test(arguments: [
        #"{"pluginId":"METADATA","action":"get","callbackPath":"OwnID.cb"}"#,
        #"{"pluginId":"METADATA","action":"get","callbackPath":"OwnID.cb","params":null}"#,
    ])
    func `Plugin message payload params can be omitted or null`(_ json: String) throws {
        let payload = try coder.decodeFromString(
            json,
            as: WebBridgePluginMessage.Payload.self
        )

        #expect(payload.params == nil)
    }

    @Test func `Plugin result success encodes only success payload`() throws {
        let result = WebBridgePluginResult.success(
            .dictionary([
                "ok": .bool(true),
                "count": .int(2),
            ])
        )

        let encoded = try decodeResultJSON(result)

        #expect(encoded["ok"] == .bool(true))
        #expect(encoded["count"] == .int(2))
        #expect(encoded["error"] == nil)
    }

    @Test func `Plugin result null success is distinct from missing success`() throws {
        let encoded = try decodeResultJSON(WebBridgePluginResult.success(.null))

        #expect(encoded == .null)
    }

    @Test func `Plugin result error adds default type and preserves explicit type`() throws {
        let defaultError = try decodeResultJSON(WebBridgePluginResult.error(message: "failed"))
        let explicitError = try decodeResultJSON(WebBridgePluginResult.error(message: "canceled", type: "ABORTED"))
        let defaultPayload = try #require(defaultError["error"])
        let explicitPayload = try #require(explicitError["error"])

        #expect(defaultPayload["message"] == .string("failed"))
        #expect(defaultPayload["type"] == .string("UNKNOWN"))
        #expect(explicitPayload["message"] == .string("canceled"))
        #expect(explicitPayload["type"] == .string("ABORTED"))
    }

    @Test func `Decoded dictionary error without type is normalized at callback boundary`() throws {
        let decodedResult = try coder.decodeFromString(
            #"{"error":{"message":"raw failure"}}"#,
            as: WebBridgePluginResult.self
        )

        let encoded = try decodeResultJSON(decodedResult)
        let error = try #require(encoded["error"])

        #expect(error["message"] == .string("raw failure"))
        #expect(error["type"] == .string("UNKNOWN"))
    }

    private func decodeResultJSON(_ result: WebBridgePluginResult) throws -> JSONValue {
        try coder.decodeFromString(result.toResultString(coder: coder), as: JSONValue.self)
    }
}
