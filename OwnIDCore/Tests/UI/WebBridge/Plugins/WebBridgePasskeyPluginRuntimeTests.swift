import Foundation
import Testing

@testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct WebBridgePasskeyPluginRuntimeTests {
    private let coder = WebBridgeTestJSONCoder()

    @Test(arguments: [
        (true, JSONValue.bool(true)),
        (false, JSONValue.bool(false)),
    ])
    func `Passkey plugin reports local FIDO capability availability`(
        _ isCapable: Bool,
        _ expected: JSONValue
    ) async {
        guard #available(iOS 16.0, *) else { return }

        let plugin = WebBridgePasskeyPlugin(
            passkey: RecordingWebBridgePasskey(),
            localInfo: WebBridgeRuntimePluginLocalInfo(isSystemFidoCapable: isCapable),
            coder: coder
        )

        let result = await handleWebBridgePlugin(plugin, pluginID: "FIDO", action: "isAvailable")

        #expect(result.success == expected)
        #expect(result.error == nil)
    }

    @Test func `Passkey get maps params to assertion options and success payload`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let passkey = RecordingWebBridgePasskey(
            assertionOutcome: .success(
                AssertionResult(
                    id: "credential-id",
                    type: .publicKey,
                    response: .init(
                        clientDataJSON: "client-data",
                        authenticatorData: "auth-data",
                        signature: "signature",
                        userHandle: "user-handle"
                    ),
                    authenticatorAttachment: .platform
                )
            )
        )
        let plugin = WebBridgePasskeyPlugin(
            passkey: passkey,
            localInfo: WebBridgeRuntimePluginLocalInfo(),
            coder: coder
        )

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "FIDO",
            action: "get",
            params: #"{"context":"challenge-context","relyingPartyId":"example.test","credsIds":["cred-one",""],"credId":"ignored"}"#
        )
        let options = try #require(passkey.assertionOptions)

        #expect(options.challenge.value == Data("challenge-context".utf8).encodeToBase64UrlSafe())
        #expect(options.rpID == "example.test")
        #expect(options.allowCredentials?.map(\.id) == ["cred-one"])
        #expect(options.userVerification == .required)
        #expect(result.success?["credentialId"] == .string("credential-id"))
        #expect(result.success?["clientDataJSON"] == .string("client-data"))
        #expect(result.success?["authenticatorData"] == .string("auth-data"))
        #expect(result.success?["signature"] == .string("signature"))
        #expect(result.success?["userHandle"] == .string("user-handle"))
        #expect(result.success?["authenticatorAttachment"] == .string("platform"))
    }

    @Test func `Passkey flow create maps params to attestation options and compact success payload`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let passkey = RecordingWebBridgePasskey(
            attestationOutcome: .success(
                AttestationResult(
                    id: "attestation-id",
                    type: .publicKey,
                    response: .init(clientDataJSON: "client-data", attestationObject: "attestation-object", transports: [.internal]),
                    authenticatorAttachment: .platform
                )
            )
        )
        let plugin = WebBridgePasskeyPlugin(
            passkey: passkey,
            localInfo: WebBridgeRuntimePluginLocalInfo(),
            coder: coder
        )

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "FIDO",
            action: "create",
            params: #"""
                {
                  "context": "create-context",
                  "relyingPartyId": "example.test",
                  "relyingPartyName": "Example",
                  "userName": "user@example.test",
                  "userDisplayName": "Example User",
                  "credId": "excluded-credential"
                }
                """#
        )
        let options = try #require(passkey.attestationOptions)

        #expect(options.challenge.value == Data("create-context".utf8).encodeToBase64UrlSafe())
        #expect(options.rp.id == "example.test")
        #expect(options.rp.name == "Example")
        #expect(options.user.name == "user@example.test")
        #expect(options.user.displayName == "Example User")
        #expect(options.pubKeyCredParams.map(\.alg) == [.ES256, .RS256])
        #expect(options.excludeCredentials?.map(\.id) == ["excluded-credential"])
        #expect(result.success?["credentialId"] == .string("attestation-id"))
        #expect(result.success?["clientDataJSON"] == .string("client-data"))
        #expect(result.success?["attestationObject"] == .string("attestation-object"))
        #expect(result.success?["authenticatorAttachment"] == .string("platform"))
    }

    @Test func `Passkey enrollment create maps WebAuthn params and success payload`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let passkey = RecordingWebBridgePasskey(
            attestationOutcome: .success(
                AttestationResult(
                    id: "enrollment-id",
                    type: .publicKey,
                    response: .init(clientDataJSON: "client-data", attestationObject: "attestation-object", transports: [.internal]),
                    authenticatorAttachment: .platform
                )
            )
        )
        let plugin = WebBridgePasskeyPlugin(
            passkey: passkey,
            localInfo: WebBridgeRuntimePluginLocalInfo(),
            coder: coder
        )

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "FIDO",
            action: "create",
            params: #"""
                {
                  "challenge": "challenge-b64",
                  "rp": { "id": "example.test", "name": "Example" },
                  "user": { "id": "user-id", "name": "user@example.test", "displayName": "Example User" },
                  "pubKeyCredParams": [
                    { "type": "public-key", "alg": -7 },
                    { "type": "public-key", "alg": 12345 }
                  ],
                  "attestation": "direct",
                  "authenticatorSelection": {
                    "authenticatorAttachment": "cross-platform",
                    "userVerification": "preferred",
                    "residentKey": "discouraged"
                  },
                  "timeout": 3000,
                  "excludeCredentials": [
                    { "id": "exclude-one", "type": "public-key", "transports": ["internal", "hybrid"] }
                  ]
                }
                """#
        )
        let options = try #require(passkey.attestationOptions)

        #expect(options.challenge.value == "challenge-b64")
        #expect(options.pubKeyCredParams.map(\.alg) == [.ES256])
        #expect(options.attestation == .direct)
        #expect(options.authenticatorSelection?.authenticatorAttachment == .crossPlatform)
        #expect(options.authenticatorSelection?.userVerification == .preferred)
        #expect(options.authenticatorSelection?.residentKey == .discouraged)
        #expect(options.timeout?.milliseconds == 3000)
        #expect(options.excludeCredentials?.first?.id == "exclude-one")
        #expect(options.excludeCredentials?.first?.transports == [.internal, .hybrid])
        #expect(result.success?["id"] == .string("enrollment-id"))
        #expect(result.success?["rawId"] == .string("enrollment-id"))
        #expect(result.success?["type"] == .string("public-key"))
        #expect(result.success?["response"]?["clientDataJSON"] == .string("client-data"))
        #expect(result.success?["response"]?["attestationObject"] == .string("attestation-object"))
        #expect(result.success?["authenticatorAttachment"] == .string("platform"))
    }

    @Test(arguments: WebBridgePasskeyErrorCase.all)
    func `Passkey plugin maps get result errors to normalized bridge error types`(
        _ testCase: WebBridgePasskeyErrorCase
    ) async throws {
        guard #available(iOS 16.0, *) else { return }

        let passkey = RecordingWebBridgePasskey(assertionOutcome: testCase.assertionOutcome)
        let plugin = WebBridgePasskeyPlugin(
            passkey: passkey,
            localInfo: WebBridgeRuntimePluginLocalInfo(),
            coder: coder
        )

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "FIDO",
            action: "get",
            params: #"{"context":"ctx","relyingPartyId":"example.test"}"#,
            coder: coder
        )

        #expect(error["type"] == .string(testCase.expectedType))
        #expect(error["message"]?.stringValue?.contains(testCase.expectedMessageFragment) == true)
    }

    @Test(arguments: WebBridgePasskeyErrorCase.all)
    func `Passkey plugin maps create result errors to normalized bridge error types`(
        _ testCase: WebBridgePasskeyErrorCase
    ) async throws {
        guard #available(iOS 16.0, *) else { return }

        let passkey = RecordingWebBridgePasskey(attestationOutcome: testCase.attestationOutcome)
        let plugin = WebBridgePasskeyPlugin(
            passkey: passkey,
            localInfo: WebBridgeRuntimePluginLocalInfo(),
            coder: coder
        )

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "FIDO",
            action: "create",
            params: #"""
                {
                  "context": "ctx",
                  "relyingPartyId": "example.test",
                  "relyingPartyName": "Example",
                  "userName": "user@example.test",
                  "userDisplayName": "Example User"
                }
                """#,
            coder: coder
        )

        #expect(error["type"] == .string(testCase.expectedType))
        #expect(error["message"]?.stringValue?.contains(testCase.expectedMessageFragment) == true)
    }

    @Test func `Passkey plugin validates malformed get and create params before calling passkey capability`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let passkey = RecordingWebBridgePasskey()
        let plugin = WebBridgePasskeyPlugin(
            passkey: passkey,
            localInfo: WebBridgeRuntimePluginLocalInfo(),
            coder: coder
        )

        let getError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "FIDO",
            action: "get",
            params: #"{"context":"   ","relyingPartyId":"example.test"}"#,
            coder: coder
        )
        let createError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "FIDO",
            action: "create",
            params:
                #"{"challenge":"challenge","rp":{"id":"example.test","name":"Example"},"user":{"name":"user","displayName":"User"},"pubKeyCredParams":[{"type":"public-key","alg":999}]}"#,
            coder: coder
        )

        #expect(getError["message"]?.stringValue?.contains("'context' cannot be empty") == true)
        #expect(createError["message"]?.stringValue?.contains("Unsupported algorithm") == true)
        #expect(passkey.assertionOptions == nil)
        #expect(passkey.attestationOptions == nil)
    }
}

private final class RecordingWebBridgePasskey: PasskeyProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedAssertionOptions: AssertionOptions?
    private var recordedAttestationOptions: AttestationOptions?
    private let assertionOutcome: PasskeyResult<AssertionResult>
    private let attestationOutcome: PasskeyResult<AttestationResult>

    init(
        assertionOutcome: PasskeyResult<AssertionResult> = .failure(.general("unexpected assertion call")),
        attestationOutcome: PasskeyResult<AttestationResult> = .failure(.general("unexpected attestation call"))
    ) {
        self.assertionOutcome = assertionOutcome
        self.attestationOutcome = attestationOutcome
    }

    var assertionOptions: AssertionOptions? {
        lock.withLock { recordedAssertionOptions }
    }

    var attestationOptions: AttestationOptions? {
        lock.withLock { recordedAttestationOptions }
    }

    @MainActor func getCredential(assertionOptions: AssertionOptions) async -> PasskeyResult<AssertionResult> {
        lock.withLock { recordedAssertionOptions = assertionOptions }
        return assertionOutcome
    }

    @MainActor func createCredential(attestationOptions: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        lock.withLock { recordedAttestationOptions = attestationOptions }
        return attestationOutcome
    }
}

struct WebBridgePasskeyErrorCase: CustomStringConvertible, Sendable {
    let description: String
    let assertionOutcome: PasskeyResult<AssertionResult>
    let attestationOutcome: PasskeyResult<AttestationResult>
    let expectedType: String
    let expectedMessageFragment: String

    static let all: [WebBridgePasskeyErrorCase] = [
        .init(
            description: "canceled",
            assertionOutcome: .canceled(.userClose(details: "dismissed")),
            attestationOutcome: .canceled(.userClose(details: "dismissed")),
            expectedType: "ABORTED",
            expectedMessageFragment: "Canceled"
        ),
        .init(
            description: "no credential",
            assertionOutcome: .failure(.passkeysNoCredential("none", nil, .noCredential)),
            attestationOutcome: .failure(.passkeysNoCredential("none", nil, .noCredential)),
            expectedType: "TYPE_NO_CREDENTIAL",
            expectedMessageFragment: "NoCredential"
        ),
        .init(
            description: "identified failure",
            assertionOutcome: .failure(.general("not interactive", nil, .notInteractive)),
            attestationOutcome: .failure(.general("not interactive", nil, .notInteractive)),
            expectedType: "NOTINTERACTIVEERROR",
            expectedMessageFragment: "NotInteractiveError"
        ),
    ]
}
