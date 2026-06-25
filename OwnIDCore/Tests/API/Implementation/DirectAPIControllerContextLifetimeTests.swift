import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct DirectAPIControllerContextLifetimeTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Email verification controller keeps start context after scope mutation`() async throws {
        let network = APIRecordingNetwork(
            responses: [
                .success(
                    success(code: 201, path: "verifications/email/start", body: verificationChallengeBody("email-lifetime-challenge"))
                ),
                .success(success(code: 200, path: "verifications/email/complete", body: #"{"accessToken":"email-complete-token"}"#)),
                .success(success(code: 204, path: "verifications/email/resend", body: "")),
                .success(success(code: 204, path: "verifications/email/cancel", body: "")),
            ]
        )
        let container = makeContainer(network: network)
        setContextAccessToken("start-email-token", in: container)

        let controller = try #require(await container.apiNamespace.verifications.email.start().getOrNil())
        setContextAccessToken("later-email-token", in: container)

        #expect((await controller.completeWithCode(code: "123456")).getOrNil() == .accessToken(AccessToken(token: "email-complete-token")))
        _ = try #require((await controller.resend()).getOrNil())
        _ = try #require((await controller.cancel(reason: .moveToOtherChallenge)).getOrNil())

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 4)
        let traceParent = try #require(
            requests.first?.buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        )
        try assertRequest(
            requests,
            at: 0,
            path: "verifications/email/start",
            accessToken: "start-email-token",
            traceParent: traceParent
        ) { body in
            #expect(body.isEmpty)
        }
        try assertRequest(
            requests,
            at: 1,
            path: "verifications/email/complete",
            accessToken: "start-email-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "email-lifetime-challenge")
            #expect(body["code"] as? String == "123456")
        }
        try assertRequest(
            requests,
            at: 2,
            path: "verifications/email/resend",
            accessToken: "start-email-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "email-lifetime-challenge")
        }
        try assertRequest(
            requests,
            at: 3,
            path: "verifications/email/cancel",
            accessToken: "start-email-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "email-lifetime-challenge")
            #expect(body["reason"] as? String == "moveToOtherChallenge")
        }
    }

    @Test func `Phone verification controller keeps start context after scope mutation`() async throws {
        let network = APIRecordingNetwork(
            responses: [
                .success(
                    success(code: 201, path: "verifications/phone/start", body: verificationChallengeBody("phone-lifetime-challenge"))
                ),
                .success(success(code: 200, path: "verifications/phone/complete", body: #"{"proofToken":"phone-proof-token"}"#)),
                .success(success(code: 204, path: "verifications/phone/resend", body: "")),
                .success(success(code: 204, path: "verifications/phone/cancel", body: "")),
            ]
        )
        let container = makeContainer(network: network)
        setContextAccessToken("start-phone-token", in: container)

        let controller = try #require(await container.apiNamespace.verifications.phone.start().getOrNil())
        setContextAccessToken("later-phone-token", in: container)

        #expect((await controller.completeWithCode(code: "654321")).getOrNil() == .proofToken(ProofToken(token: "phone-proof-token")))
        _ = try #require((await controller.resend()).getOrNil())
        _ = try #require((await controller.cancel(reason: .timeout)).getOrNil())

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 4)
        let traceParent = try #require(
            requests.first?.buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        )
        try assertRequest(
            requests,
            at: 0,
            path: "verifications/phone/start",
            accessToken: "start-phone-token",
            traceParent: traceParent
        ) { body in
            #expect(body.isEmpty)
        }
        try assertRequest(
            requests,
            at: 1,
            path: "verifications/phone/complete",
            accessToken: "start-phone-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "phone-lifetime-challenge")
            #expect(body["code"] as? String == "654321")
        }
        try assertRequest(
            requests,
            at: 2,
            path: "verifications/phone/resend",
            accessToken: "start-phone-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "phone-lifetime-challenge")
        }
        try assertRequest(
            requests,
            at: 3,
            path: "verifications/phone/cancel",
            accessToken: "start-phone-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "phone-lifetime-challenge")
            #expect(body["reason"] as? String == "timeout")
        }
    }

    @Test func `OIDC controller keeps start context and rejects mismatched completion after scope mutation`() async throws {
        let network = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "oidc/idp/start/google", body: oidcChallengeBody("oidc-lifetime-challenge"))),
                .success(
                    success(
                        code: 200,
                        path: "oidc/idp/complete",
                        body: """
                            {
                              "accessToken": "oidc-complete-token",
                              "loginId": {"id": "user@example.test", "type": "Email"},
                              "userInfo": {"email": "user@example.test"},
                              "provider": "Google"
                            }
                            """
                    )
                ),
                .success(success(code: 204, path: "oidc/idp/cancel", body: "")),
            ]
        )
        let container = makeContainer(network: network)
        setContextAccessToken("start-oidc-token", in: container)

        let controller = try #require(
            await container.apiNamespace.oidc.start(params: OIDCAPIParams(provider: .google, oauthResponseType: .code)).getOrNil()
        )
        setContextAccessToken("later-oidc-token", in: container)

        let mismatch = await controller.completeWithToken(idToken: "provider-id-token")
        guard case .failure(.badRequest(.invalidArgument)) = mismatch else {
            return try #require(nil as Void?, "Expected mismatched OIDC completion to fail locally, got \(mismatch)")
        }
        #expect(await network.requestCount() == 1)

        let complete = try #require((await controller.completeWithCode(code: "provider-code")).getOrNil())
        #expect(complete.accessToken == AccessToken(token: "oidc-complete-token"))
        _ = try #require((await controller.cancel(reason: .moveToOtherChallenge)).getOrNil())

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 3)
        let traceParent = try #require(
            requests.first?.buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        )
        try assertRequest(
            requests,
            at: 0,
            path: "oidc/idp/start/google",
            accessToken: "start-oidc-token",
            traceParent: traceParent
        ) { body in
            #expect(body["oauthResponseType"] as? String == "code")
        }
        try assertRequest(
            requests,
            at: 1,
            path: "oidc/idp/complete",
            accessToken: "start-oidc-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "oidc-lifetime-challenge")
            #expect(body["code"] as? String == "provider-code")
        }
        try assertRequest(
            requests,
            at: 2,
            path: "oidc/idp/cancel",
            accessToken: "start-oidc-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "oidc-lifetime-challenge")
            #expect(body["reason"] as? String == "moveToOtherChallenge")
        }
    }

    @Test func `Passkey assertion controller keeps start context after scope mutation`() async throws {
        let challenge = "YXNzZXJ0aW9uLWxpZmV0aW1lLWNoYWxsZW5nZQ"
        let network = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "passkeys/assertion/options", body: assertionOptionsBody(challenge))),
                .success(success(code: 200, path: "passkeys/assertion/result", body: #"{"accessToken":"assertion-access-token"}"#)),
                .success(success(code: 204, path: "passkeys/assertion/cancel", body: "")),
            ]
        )
        let container = makeContainer(network: network)
        setContextAccessToken("start-assertion-token", in: container)

        let controller = try #require(await container.apiNamespace.passkeys.assertion.start().getOrNil())
        setContextAccessToken("later-assertion-token", in: container)

        #expect((await controller.verify(assertionResult: assertionResult())).getOrNil() == AccessToken(token: "assertion-access-token"))
        _ = try #require((await controller.cancel(reason: .timeout)).getOrNil())

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 3)
        let traceParent = try #require(
            requests.first?.buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        )
        try assertRequest(
            requests,
            at: 0,
            path: "passkeys/assertion/options",
            accessToken: "start-assertion-token",
            traceParent: traceParent
        ) { body in
            #expect(body.isEmpty)
        }
        try assertRequest(
            requests,
            at: 1,
            path: "passkeys/assertion/result",
            accessToken: "start-assertion-token",
            traceParent: traceParent
        ) { body in
            #expect(body["id"] as? String == "assertion-credential-id")
        }
        try assertRequest(
            requests,
            at: 2,
            path: "passkeys/assertion/cancel",
            accessToken: nil,
            traceParent: traceParent
        ) { body in
            #expect(body["challenge"] as? String == challenge)
            #expect(body["reason"] as? String == "timeout")
        }
    }

    @Test func `Passkey attestation controller keeps start context after scope mutation`() async throws {
        let challenge = "YXR0ZXN0YXRpb24tbGlmZXRpbWUtY2hhbGxlbmdl"
        let network = APIRecordingNetwork(
            responses: [
                .success(success(code: 200, path: "passkeys/attestation/options", body: attestationOptionsBody(challenge))),
                .success(
                    success(
                        code: 200,
                        path: "passkeys/attestation/result",
                        body: #"{"proofToken":"attestation-proof-token","ownIdData":"attestation-ownid-data"}"#
                    )
                ),
                .success(success(code: 204, path: "passkeys/attestation/cancel", body: "")),
            ]
        )
        let container = makeContainer(network: network)
        setContextAccessToken("start-attestation-token", in: container)

        let controller = try #require(await container.apiNamespace.passkeys.attestation.start().getOrNil())
        setContextAccessToken("later-attestation-token", in: container)

        let verify = try #require((await controller.verify(attestationResult: attestationResult())).getOrNil())
        #expect(verify.proofToken == ProofToken(token: "attestation-proof-token"))
        _ = try #require((await controller.cancel(reason: .moveToOtherChallenge)).getOrNil())

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 3)
        let traceParent = try #require(
            requests.first?.buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        )
        try assertRequest(
            requests,
            at: 0,
            path: "passkeys/attestation/options",
            accessToken: "start-attestation-token",
            traceParent: traceParent
        ) { body in
            #expect(body.isEmpty)
        }
        try assertRequest(
            requests,
            at: 1,
            path: "passkeys/attestation/result",
            accessToken: "start-attestation-token",
            traceParent: traceParent
        ) { body in
            #expect(body["id"] as? String == "attestation-credential-id")
        }
        try assertRequest(
            requests,
            at: 2,
            path: "passkeys/attestation/cancel",
            accessToken: nil,
            traceParent: traceParent
        ) { body in
            #expect(body["challenge"] as? String == challenge)
            #expect(body["reason"] as? String == "moveToOtherChallenge")
        }
    }

    private func makeContainer(network: any NetworkProtocol) -> DIContainerImpl {
        let container = DIContainerImpl(scopeName: "DirectAPIControllerContextLifetimeTests")
        container.register((any APIBaseURL).self, instance: StaticAPIBaseURL(url: baseURL))
        container.register((any NetworkProtocol).self, instance: network)
        container.register((any JSONCoder).self, instance: coder)
        container.registerFactory { resolver -> any EmailVerificationAPI in EmailVerificationAPIImpl.create(resolver: resolver) }
        container.registerFactory { resolver -> any PhoneVerificationAPI in PhoneVerificationAPIImpl.create(resolver: resolver) }
        container.registerFactory { resolver -> any OIDCAPI in OIDCAPIImpl.create(resolver: resolver) }
        container.registerFactory { resolver -> any PasskeyAssertionAPI in PasskeyAssertionAPIImpl.create(resolver: resolver) }
        container.registerFactory { resolver -> any PasskeyAttestationAPI in PasskeyAttestationAPIImpl.create(resolver: resolver) }
        return container
    }

    private func setContextAccessToken(_ token: String, in container: DIContainerImpl) {
        _ = container.setContext { builder in
            builder.authz = .fromToken(token)
        }
    }

    private func success(code: Int, path: String, body: String) -> NetworkResponse.Success {
        NetworkResponse.Success(url: baseURL.appendingPathComponent(path), code: code, headers: [:], body: body)
    }

    private func verificationChallengeBody(_ challengeID: String) -> String {
        """
        {
          "challengeId": "\(challengeID)",
          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
          "timeout": 30000,
          "attempts": 5,
          "channel": {"channel": "u***@example.test", "id": "\(challengeID)-channel-id"},
          "methods": {"otp": {"length": 6}}
        }
        """
    }

    private func oidcChallengeBody(_ challengeID: String) -> String {
        """
        {
          "challengeId": "\(challengeID)",
          "timeout": 30000,
          "clientId": "provider-client-id"
        }
        """
    }

    private func assertionOptionsBody(_ challenge: String) -> String {
        """
        {
          "challenge": "\(challenge)",
          "rpId": "login.example.test",
          "allowCredentials": [],
          "userVerification": "required",
          "timeout": 120000
        }
        """
    }

    private func attestationOptionsBody(_ challenge: String) -> String {
        """
        {
          "rp": {"id": "login.example.test", "name": "Example RP"},
          "user": {"id": "dXNlci1oYW5kbGU", "name": "user@example.test", "displayName": "Test User"},
          "challenge": "\(challenge)",
          "pubKeyCredParams": [{"type": "public-key", "alg": -7}],
          "attestation": "direct"
        }
        """
    }

    private func assertionResult() -> AssertionResult {
        AssertionResult(
            id: "assertion-credential-id",
            type: .publicKey,
            response: .init(
                clientDataJSON: "client-data-json",
                authenticatorData: "authenticator-data",
                signature: "assertion-signature",
                userHandle: "user-handle"
            ),
            authenticatorAttachment: .platform
        )
    }

    private func attestationResult() -> AttestationResult {
        AttestationResult(
            id: "attestation-credential-id",
            type: .publicKey,
            response: .init(
                clientDataJSON: "client-data-json",
                attestationObject: "attestation-object",
                transports: [.internal, .hybrid]
            ),
            authenticatorAttachment: .platform
        )
    }

    private func assertRequest(
        _ requests: [NetworkRequest],
        at index: Int,
        path: String,
        accessToken: String?,
        traceParent: String,
        bodyAssertions: ([String: Any]) -> Void,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        try #require(requests.indices.contains(index), "Missing request at index \(index)", sourceLocation: sourceLocation)

        let request = requests[index].buildURLRequest()
        #expect(request.url == baseURL.appendingPathComponent(path), sourceLocation: sourceLocation)
        #expect(request.httpMethod == "POST", sourceLocation: sourceLocation)
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" },
            sourceLocation: sourceLocation
        )
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent,
            sourceLocation: sourceLocation
        )

        bodyAssertions(try bodyObject(from: request, sourceLocation: sourceLocation))
    }
}
