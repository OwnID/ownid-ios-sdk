import Foundation
import OwnIDCore
import Testing

struct PasskeysModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Assertion options Codable uses WebAuthn keys and values`() throws {
        let json = """
            {
              "challenge": "assertion-challenge",
              "rpId": "login.example.test",
              "allowCredentials": [
                {
                  "id": "credential-id",
                  "type": "public-key",
                  "transports": ["internal", "hybrid"]
                }
              ],
              "userVerification": "preferred",
              "timeout": 120000
            }
            """

        let options = try modelJSON.decoder.decode(AssertionOptions.self, from: Data(json.utf8))

        #expect(options.challenge == ChallengeID("assertion-challenge"))
        #expect(options.rpID == "login.example.test")
        #expect(options.userVerification == .preferred)
        #expect(options.timeout == Timeout(milliseconds: 120000))
        #expect(options.allowCredentials?.count == 1)
        #expect(options.allowCredentials?.first?.id == "credential-id")
        #expect(options.allowCredentials?.first?.type == .publicKey)
        #expect(options.allowCredentials?.first?.transports == [.internal, .hybrid])

        let encoded = try modelJSON.object(encoding: options)
        #expect(encoded["challenge"] as? String == "assertion-challenge")
        #expect(encoded["rpId"] as? String == "login.example.test")
        #expect(encoded["rpID"] == nil)
        #expect(encoded["userVerification"] as? String == "preferred")
        #expect(encoded["timeout"] as? Int == 120000)

        let credentials = try #require(encoded["allowCredentials"] as? [[String: Any]])
        #expect(credentials.first?["id"] as? String == "credential-id")
        #expect(credentials.first?["type"] as? String == "public-key")
        #expect(credentials.first?["transports"] as? [String] == ["internal", "hybrid"])
    }

    @Test func `Attestation options Codable uses WebAuthn keys and values`() throws {
        let options = AttestationOptions(
            rp: .init(id: "login.example.test", name: "Example"),
            user: .init(id: "user-handle", name: "user@example.test", displayName: "User Example"),
            challenge: ChallengeID("attestation-challenge"),
            pubKeyCredParams: [
                .init(type: .publicKey, alg: .ES256),
                .init(type: .publicKey, alg: .RS256),
            ],
            attestation: .direct,
            authenticatorSelection: .init(
                authenticatorAttachment: .crossPlatform,
                userVerification: .required,
                residentKey: .preferred
            ),
            timeout: Timeout(milliseconds: 60000),
            excludeCredentials: [
                .init(id: "excluded-credential", type: .publicKey, transports: [.usb, .smartCard])
            ]
        )

        let encoded = try modelJSON.object(encoding: options)

        #expect((encoded["rp"] as? [String: Any])?["id"] as? String == "login.example.test")
        #expect((encoded["rp"] as? [String: Any])?["name"] as? String == "Example")
        #expect((encoded["user"] as? [String: Any])?["id"] as? String == "user-handle")
        #expect((encoded["user"] as? [String: Any])?["name"] as? String == "user@example.test")
        #expect((encoded["user"] as? [String: Any])?["displayName"] as? String == "User Example")
        #expect(encoded["challenge"] as? String == "attestation-challenge")
        #expect(encoded["attestation"] as? String == "direct")
        #expect(encoded["timeout"] as? Int == 60000)

        let params = try #require(encoded["pubKeyCredParams"] as? [[String: Any]])
        #expect(params.map { $0["type"] as? String } == ["public-key", "public-key"])
        #expect(params.map { $0["alg"] as? Int } == [-7, -257])

        let selection = try #require(encoded["authenticatorSelection"] as? [String: Any])
        #expect(selection["authenticatorAttachment"] as? String == "cross-platform")
        #expect(selection["userVerification"] as? String == "required")
        #expect(selection["residentKey"] as? String == "preferred")

        let excluded = try #require(encoded["excludeCredentials"] as? [[String: Any]])
        #expect(excluded.first?["id"] as? String == "excluded-credential")
        #expect(excluded.first?["type"] as? String == "public-key")
        #expect(excluded.first?["transports"] as? [String] == ["usb", "smart-card"])

        let decoded = try modelJSON.decoder.decode(AttestationOptions.self, from: try modelJSON.data(encoding: options))
        #expect(decoded.rp.id == "login.example.test")
        #expect(decoded.user.id == "user-handle")
        #expect(decoded.pubKeyCredParams.map(\.alg) == [.ES256, .RS256])
        #expect(decoded.authenticatorSelection?.authenticatorAttachment == .crossPlatform)
        #expect(decoded.excludeCredentials?.first?.transports == [.usb, .smartCard])
    }

    @Test func `WebAuthn result Codable preserves response fields and omits nil attachments`() throws {
        let assertion = AssertionResult(
            id: "assertion-credential-id",
            type: .publicKey,
            response: .init(
                clientDataJSON: "assertion-client-data",
                authenticatorData: "authenticator-data",
                signature: "signature",
                userHandle: nil
            ),
            authenticatorAttachment: nil
        )
        let attestation = AttestationResult(
            id: "attestation-credential-id",
            type: .publicKey,
            response: .init(
                clientDataJSON: "attestation-client-data",
                attestationObject: "attestation-object",
                transports: [.internal, .hybrid]
            ),
            authenticatorAttachment: .platform
        )

        let encodedAssertion = try modelJSON.object(encoding: assertion)
        #expect(encodedAssertion["id"] as? String == "assertion-credential-id")
        #expect(encodedAssertion["type"] as? String == "public-key")
        #expect(encodedAssertion["authenticatorAttachment"] == nil)

        let assertionResponse = try #require(encodedAssertion["response"] as? [String: Any])
        #expect(assertionResponse["clientDataJSON"] as? String == "assertion-client-data")
        #expect(assertionResponse["authenticatorData"] as? String == "authenticator-data")
        #expect(assertionResponse["signature"] as? String == "signature")
        #expect(assertionResponse["userHandle"] == nil)

        let encodedAttestation = try modelJSON.object(encoding: attestation)
        #expect(encodedAttestation["id"] as? String == "attestation-credential-id")
        #expect(encodedAttestation["type"] as? String == "public-key")
        #expect(encodedAttestation["authenticatorAttachment"] as? String == "platform")

        let attestationResponse = try #require(encodedAttestation["response"] as? [String: Any])
        #expect(attestationResponse["clientDataJSON"] as? String == "attestation-client-data")
        #expect(attestationResponse["attestationObject"] as? String == "attestation-object")
        #expect(attestationResponse["transports"] as? [String] == ["internal", "hybrid"])

        let decodedAssertion = try modelJSON.decoder.decode(AssertionResult.self, from: try modelJSON.data(encoding: assertion))
        #expect(decodedAssertion.authenticatorAttachment == nil)
        #expect(decodedAssertion.response.userHandle == nil)

        let decodedAttestation = try modelJSON.decoder.decode(AttestationResult.self, from: try modelJSON.data(encoding: attestation))
        #expect(decodedAttestation.authenticatorAttachment == .platform)
        #expect(decodedAttestation.response.transports == [.internal, .hybrid])
    }

    @Test func `WebAuthn enum decoding rejects unknown raw values`() {
        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(CredentialType.self, from: Data(#""password""#.utf8))
        }
        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(AuthenticatorAttachment.self, from: Data(#""roaming""#.utf8))
        }
        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(UserVerification.self, from: Data(#""always""#.utf8))
        }
        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(KeyAlgorithmType.self, from: Data("0".utf8))
        }
    }
}
