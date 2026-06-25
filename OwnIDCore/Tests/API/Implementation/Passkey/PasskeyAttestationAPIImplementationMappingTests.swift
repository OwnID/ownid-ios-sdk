import Foundation
import Testing

@testable import OwnIDCore

struct PasskeyAttestationAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Options request builds attestation endpoint body and headers`() throws {
        let call = try PasskeyAttestationOptionsAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "user@example.test", type: .email),
            accountDisplayName: "Test User",
            accessToken: AccessToken(token: "session-access-token"),
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)
        let loginID = try #require(body["loginId"] as? [String: Any])

        #expect(request.url == baseURL.appendingPathComponent("passkeys/attestation/options"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer session-access-token")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        #expect(loginID["id"] as? String == "user@example.test")
        #expect(loginID["type"] as? String == "Email")
        #expect(body["accountDisplayName"] as? String == "Test User")
        #expect(body.keys.sorted() == ["accountDisplayName", "loginId"])
    }

    @Test func `Options request uses default empty body when no optional inputs are provided`() throws {
        let call = try PasskeyAttestationOptionsAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: nil,
            accountDisplayName: nil,
            accessToken: nil,
            traceParent: nil
        )

        let request = call.request.buildURLRequest()

        #expect(request.url == baseURL.appendingPathComponent("passkeys/attestation/options"))
        #expect(request.httpMethod == "POST")
        #expect(String(data: try #require(request.httpBody), encoding: .utf8) == "{}")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == nil)
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == nil)
    }

    @Test func `Options success maps server DTO to attestation options`() throws {
        let result = try makeOptionsCall().mapHttpSuccess(
            success(
                code: 200,
                path: "passkeys/attestation/options",
                body: """
                    {
                      "rp": {"id": "login.example.test", "name": "Example RP"},
                      "user": {"id": "dXNlci1oYW5kbGU", "name": "user@example.test", "displayName": "Test User"},
                      "challenge": "YXR0ZXN0YXRpb24tY2hhbGxlbmdl",
                      "pubKeyCredParams": [
                        {"type": "public-key", "alg": -7},
                        {"type": "public-key", "alg": -257}
                      ],
                      "attestation": "direct",
                      "authenticatorSelection": {
                        "authenticatorAttachment": "platform",
                        "userVerification": "required",
                        "residentKey": "preferred"
                      },
                      "timeout": 120000,
                      "excludeCredentials": [
                        {
                          "id": "ZXhjbHVkZWQtY3JlZGVudGlhbA",
                          "type": "public-key",
                          "transports": ["internal", "hybrid", "smart-card"]
                        }
                      ]
                    }
                    """
            )
        )

        guard case .success(let options) = result else {
            Issue.record("Expected attestation options success, got \(result)")
            return
        }

        #expect(options.rp.id == "login.example.test")
        #expect(options.rp.name == "Example RP")
        #expect(options.user.id == "dXNlci1oYW5kbGU")
        #expect(options.user.name == "user@example.test")
        #expect(options.user.displayName == "Test User")
        #expect(options.challenge == ChallengeID("YXR0ZXN0YXRpb24tY2hhbGxlbmdl"))
        #expect(options.pubKeyCredParams.map(\.alg) == [.ES256, .RS256])
        #expect(options.pubKeyCredParams.map(\.type) == [.publicKey, .publicKey])
        #expect(options.attestation == .direct)
        #expect(options.authenticatorSelection?.authenticatorAttachment == .platform)
        #expect(options.authenticatorSelection?.userVerification == .required)
        #expect(options.authenticatorSelection?.residentKey == .preferred)
        #expect(options.timeout == Timeout(milliseconds: 120000))
        #expect(options.excludeCredentials?.first?.id == "ZXhjbHVkZWQtY3JlZGVudGlhbA")
        #expect(options.excludeCredentials?.first?.type == .publicKey)
        #expect(options.excludeCredentials?.first?.transports == [.internal, .hybrid, .smartCard])
    }

    @Test func `Options success accepts padded Base64url attestation options`() throws {
        let userID = paddedBase64URL("ab")
        let challenge = paddedBase64URL("a")
        let credentialID = paddedBase64URL("credential")

        let result = try makeOptionsCall().mapHttpSuccess(
            success(
                code: 200,
                path: "passkeys/attestation/options",
                body: """
                    {
                      "rp": {"id": "login.example.test", "name": "Example RP"},
                      "user": {"id": "\(userID)", "name": "user@example.test", "displayName": "Test User"},
                      "challenge": "\(challenge)",
                      "pubKeyCredParams": [{"type": "public-key", "alg": -7}],
                      "excludeCredentials": [
                        {"id": "\(credentialID)", "type": "public-key"}
                      ]
                    }
                    """
            )
        )

        let options = try requireSuccess(result)

        #expect(options.rp.id == "login.example.test")
        #expect(options.user.id == userID)
        #expect(options.challenge == ChallengeID(challenge))
        #expect(options.pubKeyCredParams.map(\.alg) == [.ES256])
        #expect(options.excludeCredentials?.first?.id == credentialID)
        #expect(options.excludeCredentials?.first?.type == .publicKey)
    }

    @Test(arguments: AttestationOptionsMalformedBase64URLField.allCases)
    fileprivate func `Malformed Base64url attestation option fields map to unexpected`(
        _ field: AttestationOptionsMalformedBase64URLField
    ) throws {
        let result = try makeOptionsCall().mapHttpSuccess(
            success(
                code: 200,
                path: "passkeys/attestation/options",
                body: field.responseBody
            )
        )

        try assertOptionsUnexpectedResponseError(try requireFailure(result), statusCode: 200)
    }

    @Test func `Options success defaults supported algorithms when server omits them`() throws {
        let result = try makeOptionsCall().mapHttpSuccess(
            success(
                code: 200,
                path: "passkeys/attestation/options",
                body: """
                    {
                      "rp": {"id": "login.example.test", "name": "Example RP"},
                      "user": {"id": "dXNlci1oYW5kbGU", "name": "user@example.test", "displayName": "Test User"},
                      "challenge": "YXR0ZXN0YXRpb24tY2hhbGxlbmdl",
                      "pubKeyCredParams": []
                    }
                    """
            )
        )

        guard case .success(let options) = result else {
            Issue.record("Expected attestation options success, got \(result)")
            return
        }

        #expect(options.pubKeyCredParams.map(\.alg) == [.ES256, .RS256])
        #expect(options.pubKeyCredParams.map(\.type) == [.publicKey, .publicKey])
    }

    @Test func `Options HTTP errors map start failure contracts`() throws {
        assertOptionsInvalidLoginID(
            try makeOptionsCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "passkeys/attestation/options",
                    body: """
                        {
                          "errorCode": "login_id_validation_failed",
                          "message": "Login ID does not match",
                          "loginId": {"id": "bad", "type": "Email"},
                          "regex": "^[^@]+@example\\\\.test$"
                        }
                        """
                )
            )
        )
        assertOptionsForbidden(
            try makeOptionsCall().mapHttpError(
                httpError(
                    statusCode: 403,
                    path: "passkeys/attestation/options",
                    body: #"{"errorCode":"forbidden","message":"Passkey attestation is forbidden"}"#
                )
            )
        )
        assertOptionsProviderFailed(
            try makeOptionsCall().mapHttpError(
                httpError(
                    statusCode: 424,
                    path: "passkeys/attestation/options",
                    body: """
                        {
                          "errorCode": "integration_error",
                          "message": "Passkey attestation provider failed",
                          "scope": "data"
                        }
                        """
                )
            )
        )
        assertOptionsMaximumChallenges(
            try makeOptionsCall().mapHttpError(
                httpError(
                    statusCode: 429,
                    path: "passkeys/attestation/options",
                    body: #"{"errorCode":"maximum_challenges_reached","message":"Too many passkey challenges"}"#
                )
            )
        )
    }

    @Test func `Start with params returns controller that reuses captured values`() async throws {
        let traceParent = "00-11111111111111111111111111111111-2222222222222222-01"
        let network = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 200,
                        path: "passkeys/attestation/options",
                        body: attestationOptionsBody(challenge: "YXR0ZXN0YXRpb24tcGFyYW1zLWNoYWxsZW5nZQ")
                    )
                ),
                .success(
                    success(
                        code: 200,
                        path: "passkeys/attestation/result",
                        body: #"{"proofToken":"verified-proof-token","ownIdData":"verified-ownid-data"}"#
                    )
                ),
                .success(success(code: 204, path: "passkeys/attestation/cancel", body: "")),
            ]
        )
        let api = makeAPI(network: network, context: nil)

        let startResult = await api.start(
            params: PasskeyAttestationAPIParams(
                loginID: LoginID(id: "params@example.test", type: .email),
                accountDisplayName: "Params User",
                accessToken: AccessToken(token: "params-access-token"),
                traceParent: traceParent
            )
        )
        let controller = try #require(startResult.getOrNil())

        #expect(controller.attestationOptions.challenge == ChallengeID("YXR0ZXN0YXRpb24tcGFyYW1zLWNoYWxsZW5nZQ"))
        assertAttestationStartRequest(
            try #require(await network.request(at: 0)).buildURLRequest(),
            loginID: "params@example.test",
            accountDisplayName: "Params User",
            accessToken: "params-access-token",
            traceParent: traceParent
        )

        guard case .success(let response) = await controller.verify(attestationResult: makeAttestationResult()) else {
            Issue.record("Expected attestation verify success")
            return
        }
        #expect(response.proofToken == ProofToken(token: "verified-proof-token"))
        #expect(response.ownIdData == "verified-ownid-data")

        guard case .success = await controller.cancel(reason: .moveToOtherChallenge) else {
            Issue.record("Expected attestation cancel success")
            return
        }

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 3)
        assertAttestationVerifyRequest(
            requests[1].buildURLRequest(),
            accessToken: "params-access-token",
            traceParent: traceParent
        )
        assertAttestationCancelRequest(
            requests[2].buildURLRequest(),
            challenge: "YXR0ZXN0YXRpb24tcGFyYW1zLWNoYWxsZW5nZQ",
            reason: "moveToOtherChallenge",
            traceParent: traceParent
        )
    }

    @Test func `Start uses context login ID account display name and access token fallbacks`() async throws {
        let loginIDNetwork = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 200,
                        path: "passkeys/attestation/options",
                        body: attestationOptionsBody(challenge: "YXR0ZXN0YXRpb24tY29udGV4dC1sb2dpbi1pZA")
                    )
                )
            ]
        )
        let loginIDAPI = makeAPI(
            network: loginIDNetwork,
            context: makeContext(authz: .start("context@example.test", type: .email), accountDisplayName: "Context User")
        )

        guard case .success = await loginIDAPI.start(params: nil) else {
            Issue.record("Expected attestation context login ID start success")
            return
        }
        assertAttestationStartRequest(
            try #require(await loginIDNetwork.request(at: 0)).buildURLRequest(),
            loginID: "context@example.test",
            accountDisplayName: "Context User",
            accessToken: nil,
            traceParent: nil
        )

        let accessTokenNetwork = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 200,
                        path: "passkeys/attestation/options",
                        body: attestationOptionsBody(challenge: "YXR0ZXN0YXRpb24tY29udGV4dC10b2tlbg")
                    )
                ),
                .success(
                    success(
                        code: 200,
                        path: "passkeys/attestation/result",
                        body: #"{"proofToken":"context-proof-token","ownIdData":"context-ownid-data"}"#
                    )
                ),
            ]
        )
        let accessTokenAPI = makeAPI(
            network: accessTokenNetwork,
            context: makeContext(authz: .fromToken(AccessToken(token: "context-access-token")), accountDisplayName: "Token User")
        )
        let controller = try #require((await accessTokenAPI.start(params: nil)).getOrNil())
        guard case .success = await controller.verify(attestationResult: makeAttestationResult()) else {
            Issue.record("Expected attestation context access-token verify success")
            return
        }

        let requests = await accessTokenNetwork.requestsSnapshot()
        #expect(requests.count == 2)
        let startRequest = requests[0].buildURLRequest()
        assertAttestationStartRequest(
            startRequest,
            loginID: nil,
            accountDisplayName: "Token User",
            accessToken: "context-access-token",
            traceParent: nil
        )
        assertAttestationVerifyRequest(
            requests[1].buildURLRequest(),
            accessToken: "context-access-token",
            traceParent: startRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        )
    }

    @Test func `Caller cancellation does not send server-side cancel`() async throws {
        let startNetwork = APIRecordingNetwork(suspendingAfter: [])
        let startAPI = makeAPI(network: startNetwork, context: nil)
        let startTask = Task {
            await startAPI.start(
                params: PasskeyAttestationAPIParams(
                    loginID: LoginID(id: "cancel-start@example.test", type: .email),
                    accountDisplayName: "Cancel User",
                    accessToken: nil,
                    traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00"
                )
            )
        }
        await confirmation("attestation start request was sent before task cancellation") { requestSent in
            await startNetwork.waitForRequestCount(1)
            requestSent()
            startTask.cancel()
        }
        guard case .canceled = await startTask.value else {
            Issue.record("Expected attestation start task cancellation")
            return
        }
        #expect(await startNetwork.requestPaths() == ["/api/passkeys/attestation/options"])

        let verifyNetwork = APIRecordingNetwork(suspendingAfter: [])
        let controller = PasskeyAttestationAPIControllerImpl(
            apiBaseURL: baseURL,
            network: verifyNetwork,
            coder: coder,
            attestationOptions: AttestationOptions(
                rp: .init(id: "login.example.test", name: "Example RP"),
                user: .init(id: "dXNlci1oYW5kbGU", name: "user@example.test", displayName: "Test User"),
                challenge: ChallengeID("controller-cancel-challenge"),
                pubKeyCredParams: [.init(type: .publicKey, alg: .ES256)],
                attestation: .direct,
                authenticatorSelection: nil,
                timeout: nil,
                excludeCredentials: nil
            ),
            accessToken: AccessToken(token: "controller-access-token"),
            traceParent: "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-01",
            interceptor: nil
        )
        let verifyTask = Task { await controller.verify(attestationResult: makeAttestationResult()) }
        await confirmation("attestation verify request was sent before task cancellation") { requestSent in
            await verifyNetwork.waitForRequestCount(1)
            requestSent()
            verifyTask.cancel()
        }
        guard case .canceled = await verifyTask.value else {
            Issue.record("Expected attestation verify task cancellation")
            return
        }
        #expect(await verifyNetwork.requestPaths() == ["/api/passkeys/attestation/result"])
    }

    @Test func `Verify request builds attestation result endpoint body and headers`() throws {
        let call = try PasskeyAttestationResultAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            attestationResult: AttestationResult(
                id: "credential-id",
                type: .publicKey,
                response: .init(
                    clientDataJSON: "client-data-json",
                    attestationObject: "attestation-object",
                    transports: [.internal, .hybrid, .smartCard]
                ),
                authenticatorAttachment: .platform
            ),
            accessToken: AccessToken(token: "verify-access-token"),
            traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)
        let response = try #require(body["response"] as? [String: Any])

        #expect(request.url == baseURL.appendingPathComponent("passkeys/attestation/result"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer verify-access-token")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
        )
        #expect(body["id"] as? String == "credential-id")
        #expect(body["type"] as? String == "public-key")
        #expect(body["authenticatorAttachment"] as? String == "platform")
        #expect(response["clientDataJSON"] as? String == "client-data-json")
        #expect(response["attestationObject"] as? String == "attestation-object")
        #expect(response["transports"] as? [String] == ["internal", "hybrid", "smart-card"])
    }

    @Test func `Verify success extracts and preserves raw OwnID data object`() throws {
        let result = try makeVerifyCall().mapHttpSuccess(
            success(
                code: 200,
                path: "passkeys/attestation/result",
                body: """
                    {
                      "proofToken": "proof-token",
                      "ownIdData": {"vendor":"example","nested":{"keep":true},"items":[1,"two"]}
                    }
                    """
            )
        )

        guard case .success(let response) = result else {
            Issue.record("Expected attestation verify success, got \(result)")
            return
        }
        #expect(response.proofToken == ProofToken(token: "proof-token"))
        #expect(response.ownIdData == #"{"vendor":"example","nested":{"keep":true},"items":[1,"two"]}"#)
    }

    @Test func `Verify success extracts string OwnID data value`() throws {
        let result = try makeVerifyCall().mapHttpSuccess(
            success(
                code: 200,
                path: "passkeys/attestation/result",
                body: #"{"proofToken":"proof-token","ownIdData":"opaque-ownid-data"}"#
            )
        )

        guard case .success(let response) = result else {
            Issue.record("Expected attestation verify success, got \(result)")
            return
        }
        #expect(response.ownIdData == "opaque-ownid-data")
    }

    @Test func `Verify HTTP errors map source-owned failure contracts`() throws {
        let blankUnauthorized = httpError(statusCode: 401, path: "passkeys/attestation/result", body: " \n ")
        assertVerifyUnauthorized(
            try makeVerifyCall().mapHttpError(blankUnauthorized),
            message: String(describing: NetworkResponse.Fail.httpError(blankUnauthorized))
        )

        assertVerifyUnauthorized(
            try makeVerifyCall().mapHttpError(
                httpError(
                    statusCode: 401,
                    path: "passkeys/attestation/result",
                    body: #"{"errorCode":"unauthorized","message":"Access token is invalid"}"#
                )
            )
        )
        assertVerifyForbidden(
            try makeVerifyCall().mapHttpError(
                httpError(
                    statusCode: 403,
                    path: "passkeys/attestation/result",
                    body: #"{"errorCode":"forbidden","message":"Passkey attestation result is forbidden"}"#
                )
            )
        )
        assertVerifyUserNotFound(
            try makeVerifyCall().mapHttpError(
                httpError(
                    statusCode: 404,
                    path: "passkeys/attestation/result",
                    body: #"{"errorCode":"user_not_found","message":"Passkey attestation user not found"}"#
                )
            )
        )
        assertVerifyMaximumAttemptsReached(
            try makeVerifyCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "passkeys/attestation/result",
                    body: """
                        {
                          "errorCode": "maximum_attempts_reached",
                          "message": "Maximum attempts reached",
                          "challengeId": "expired-challenge"
                        }
                        """
                )
            )
        )
        assertVerifyUnexpected(
            try makeVerifyCall().mapHttpError(
                httpError(
                    statusCode: 500,
                    path: "passkeys/attestation/result",
                    body: #"{"errorCode":"server_error","message":"Unhandled"}"#
                )
            )
        )
    }

    @Test func `Cancel request builds attestation cancel endpoint body and maps no-content success`() throws {
        let call = try PasskeyAttestationCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challenge: ChallengeID("attestation-challenge"),
            reason: .moveToOtherChallenge,
            traceParent: "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-00"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)

        #expect(request.url == baseURL.appendingPathComponent("passkeys/attestation/cancel"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == nil)
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-00"
        )
        #expect(body["challenge"] as? String == "attestation-challenge")
        #expect(body["reason"] as? String == "moveToOtherChallenge")
        #expect(body.keys.sorted() == ["challenge", "reason"])

        guard case .success = call.mapHttpSuccess(success(code: 204, path: "passkeys/attestation/cancel", body: "")) else {
            Issue.record("Expected attestation cancel success")
            return
        }
        guard
            case .failure(.unexpected(let errorCode, _, _)) =
                call.mapHttpSuccess(success(code: 200, path: "passkeys/attestation/cancel", body: ""))
        else {
            Issue.record("Expected attestation cancel unexpected failure for non-204 success")
            return
        }
        #expect(errorCode == .unknown)
    }

    @Test func `Cancel HTTP errors map failure contracts`() throws {
        assertCancelMaximumAttemptsReached(
            try makeCancelCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "passkeys/attestation/cancel",
                    body: """
                        {
                          "errorCode": "maximum_attempts_reached",
                          "message": "Maximum attempts reached",
                          "challengeId": "expired-challenge"
                        }
                        """
                )
            )
        )
        assertCancelUnexpected(
            try makeCancelCall().mapHttpError(
                httpError(
                    statusCode: 500,
                    path: "passkeys/attestation/cancel",
                    body: #"{"errorCode":"server_error","message":"Unhandled"}"#
                )
            )
        )
    }

    private func makeOptionsCall() throws -> PasskeyAttestationOptionsAPICall {
        try PasskeyAttestationOptionsAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: nil,
            accountDisplayName: nil,
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeAPI(network: any NetworkProtocol, context: Context?) -> PasskeyAttestationAPIImpl {
        PasskeyAttestationAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: context,
            loginIDValidator: nil,
            interceptor: nil
        )
    }

    private func makeContext(authz: Authz, accountDisplayName: String) -> Context {
        var builder = Context.Builder()
        builder.authz = authz
        builder.accountDisplayName = accountDisplayName
        return builder.build(scopeName: "test")
    }

    private func makeVerifyCall() throws -> PasskeyAttestationResultAPICall {
        try PasskeyAttestationResultAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            attestationResult: AttestationResult(
                id: "credential-id",
                type: .publicKey,
                response: .init(
                    clientDataJSON: "client-data-json",
                    attestationObject: "attestation-object",
                    transports: [.internal, .hybrid]
                ),
                authenticatorAttachment: .platform
            ),
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeAttestationResult() -> AttestationResult {
        AttestationResult(
            id: "credential-id",
            type: .publicKey,
            response: .init(
                clientDataJSON: "client-data-json",
                attestationObject: "attestation-object",
                transports: [.internal, .hybrid]
            ),
            authenticatorAttachment: .platform
        )
    }

    private func makeCancelCall() throws -> PasskeyAttestationCancelAPICall {
        try PasskeyAttestationCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challenge: ChallengeID("attestation-challenge"),
            reason: .timeout,
            traceParent: nil
        )
    }

    private func success(code: Int, path: String, body: String) -> NetworkResponse.Success {
        NetworkResponse.Success(url: baseURL.appendingPathComponent(path), code: code, headers: [:], body: body)
    }

    private func httpError(statusCode: Int, path: String, body: String) -> NetworkResponse.Fail.HttpError {
        NetworkResponse.Fail.HttpError(url: baseURL.appendingPathComponent(path), statusCode: statusCode, headers: [:], body: body)
    }

    private func attestationOptionsBody(challenge: String) -> String {
        """
        {
          "rp": {"id": "login.example.test", "name": "Example RP"},
          "user": {"id": "dXNlci1oYW5kbGU", "name": "user@example.test", "displayName": "Test User"},
          "challenge": "\(challenge)",
          "pubKeyCredParams": [{"type": "public-key", "alg": -7}],
          "attestation": "direct",
          "authenticatorSelection": {
            "authenticatorAttachment": "platform",
            "userVerification": "required",
            "residentKey": "preferred"
          },
          "timeout": 120000,
          "excludeCredentials": []
        }
        """
    }

    private func assertAttestationStartRequest(
        _ request: URLRequest,
        loginID: String?,
        accountDisplayName: String?,
        accessToken: String?,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("passkeys/attestation/options"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        if let traceParent {
            #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)
        } else {
            #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) != nil)
        }

        do {
            let body = try bodyObject(from: request)
            if let loginID {
                let bodyLoginID = try #require(body["loginId"] as? [String: Any])
                #expect(bodyLoginID["id"] as? String == loginID)
                #expect(bodyLoginID["type"] as? String == "Email")
            } else {
                #expect(body["loginId"] == nil)
            }
            #expect(body["accountDisplayName"] as? String == accountDisplayName)
        } catch {
            Issue.record("Failed to decode attestation start body: \(error)")
        }
    }

    private func assertAttestationVerifyRequest(
        _ request: URLRequest,
        accessToken: String?,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("passkeys/attestation/result"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            let body = try bodyObject(from: request)
            let response = try #require(body["response"] as? [String: Any])
            #expect(body["id"] as? String == "credential-id")
            #expect(body["type"] as? String == "public-key")
            #expect(response["attestationObject"] as? String == "attestation-object")
        } catch {
            Issue.record("Failed to decode attestation verify body: \(error)")
        }
    }

    private func assertAttestationCancelRequest(
        _ request: URLRequest,
        challenge: String,
        reason: String,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("passkeys/attestation/cancel"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == nil)
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            let body = try bodyObject(from: request)
            #expect(body["challenge"] as? String == challenge)
            #expect(body["reason"] as? String == reason)
            #expect(body.keys.sorted() == ["challenge", "reason"])
        } catch {
            Issue.record("Failed to decode attestation cancel body: \(error)")
        }
    }

    private func assertOptionsInvalidLoginID(
        _ failure: PasskeyAttestationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidLoginID(let errorCode, let message, let loginID, let regex)) = failure else {
            Issue.record("Expected options invalid login ID failure, got \(failure)")
            return
        }
        #expect(errorCode == .loginIDValidationFailed)
        #expect(message == "Login ID does not match")
        #expect(loginID == LoginID(id: "bad", type: .email))
        #expect(regex == #"^[^@]+@example\.test$"#)
    }

    private func assertOptionsForbidden(
        _ failure: PasskeyAttestationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected options forbidden failure, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "Passkey attestation is forbidden")
    }

    private func assertOptionsProviderFailed(
        _ failure: PasskeyAttestationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected options provider failed failure, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Passkey attestation provider failed")
        #expect(scope == .data)
    }

    private func assertOptionsMaximumChallenges(
        _ failure: PasskeyAttestationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .maximumChallengesReached(let errorCode, let message) = failure else {
            Issue.record("Expected options maximum challenges failure, got \(failure)")
            return
        }
        #expect(errorCode == .maximumChallengesReached)
        #expect(message == "Too many passkey challenges")
    }

    private func assertOptionsUnexpectedResponseError(
        _ failure: PasskeyAttestationStartAPIFailure,
        statusCode: Int,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            _ = try #require(nil as Void?, "Expected options unexpected failure, got \(failure)", sourceLocation: sourceLocation)
            return
        }

        try assertAPIUnexpectedResponseError(
            errorCode: errorCode,
            underlyingError: underlyingError,
            statusCode: statusCode,
            sourceLocation: sourceLocation
        )
    }

    private func assertVerifyUnauthorized(
        _ failure: PasskeyAttestationVerifyAPIFailure,
        message expectedMessage: String = "Access token is invalid",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unauthorized(let errorCode, let message) = failure else {
            Issue.record("Expected verify unauthorized failure, got \(failure)")
            return
        }
        #expect(errorCode == .unauthorized)
        #expect(message == expectedMessage)
    }

    private func assertVerifyForbidden(
        _ failure: PasskeyAttestationVerifyAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected verify forbidden failure, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "Passkey attestation result is forbidden")
    }

    private func assertVerifyUserNotFound(
        _ failure: PasskeyAttestationVerifyAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .userNotFound(let errorCode, let message) = failure else {
            Issue.record("Expected verify user not found failure, got \(failure)")
            return
        }
        #expect(errorCode == .userNotFound)
        #expect(message == "Passkey attestation user not found")
    }

    private func assertVerifyMaximumAttemptsReached(
        _ failure: PasskeyAttestationVerifyAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.maximumAttemptsReached(let errorCode, let message, let challengeID)) = failure else {
            Issue.record("Expected verify maximum attempts failure, got \(failure)")
            return
        }
        #expect(errorCode == .maximumAttemptsReached)
        #expect(message == "Maximum attempts reached")
        #expect(challengeID == ChallengeID("expired-challenge"))
    }

    private func assertVerifyUnexpected(
        _ failure: PasskeyAttestationVerifyAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unexpected(let errorCode, _, _) = failure else {
            Issue.record("Expected verify unexpected failure, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertCancelMaximumAttemptsReached(
        _ failure: PasskeyAttestationCancelAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.maximumAttemptsReached(let errorCode, let message, let challengeID)) = failure else {
            Issue.record("Expected cancel maximum attempts failure, got \(failure)")
            return
        }
        #expect(errorCode == .maximumAttemptsReached)
        #expect(message == "Maximum attempts reached")
        #expect(challengeID == ChallengeID("expired-challenge"))
    }

    private func assertCancelUnexpected(
        _ failure: PasskeyAttestationCancelAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unexpected(let errorCode, _, _) = failure else {
            Issue.record("Expected cancel unexpected failure, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
    }
}

private enum AttestationOptionsMalformedBase64URLField: CaseIterable, Sendable, CustomTestStringConvertible {
    case userID
    case challenge
    case excludeCredentialID

    var testDescription: String {
        switch self {
        case .userID: return "user.id"
        case .challenge: return "challenge"
        case .excludeCredentialID: return "excludeCredentials.id"
        }
    }

    var responseBody: String {
        switch self {
        case .userID:
            return body(userID: "YQ=", challenge: paddedBase64URL("a"), excludeCredentialID: paddedBase64URL("credential"))
        case .challenge:
            return body(userID: paddedBase64URL("ab"), challenge: "YQ=", excludeCredentialID: paddedBase64URL("credential"))
        case .excludeCredentialID:
            return body(userID: paddedBase64URL("ab"), challenge: paddedBase64URL("a"), excludeCredentialID: "YQ=")
        }
    }

    private func body(userID: String, challenge: String, excludeCredentialID: String) -> String {
        """
        {
          "rp": {"id": "login.example.test", "name": "Example RP"},
          "user": {"id": "\(userID)", "name": "user@example.test", "displayName": "Test User"},
          "challenge": "\(challenge)",
          "pubKeyCredParams": [{"type": "public-key", "alg": -7}],
          "excludeCredentials": [
            {"id": "\(excludeCredentialID)", "type": "public-key"}
          ]
        }
        """
    }
}
