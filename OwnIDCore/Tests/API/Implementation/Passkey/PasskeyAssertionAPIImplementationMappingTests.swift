import Foundation
import Testing

@testable import OwnIDCore

struct PasskeyAssertionAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Options request builds assertion endpoint body and headers`() throws {
        let call = try PasskeyAssertionOptionsAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "user@example.test", type: .email),
            accessToken: AccessToken(token: "session-access-token"),
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)
        let loginID = try #require(body["loginId"] as? [String: Any])

        #expect(request.url == baseURL.appendingPathComponent("passkeys/assertion/options"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer session-access-token")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        #expect(loginID["id"] as? String == "user@example.test")
        #expect(loginID["type"] as? String == "Email")
        #expect(body.keys.sorted() == ["loginId"])
    }

    @Test func `Options success maps server DTO to assertion options`() throws {
        let call = try makeOptionsCall()
        let result = call.mapHttpSuccess(
            success(
                code: 201,
                path: "passkeys/assertion/options",
                body: """
                    {
                      "challenge": "Y2hhbGxlbmdlLWJ5dGVz",
                      "rpId": "login.example.test",
                      "allowCredentials": [
                        {
                          "id": "Y3JlZGVudGlhbC1pZA",
                          "type": "public-key",
                          "transports": ["internal", "hybrid", "smart-card"]
                        }
                      ],
                      "userVerification": "required",
                      "timeout": 120000
                    }
                    """
            )
        )

        guard case .success(let options) = result else {
            Issue.record("Expected assertion options success, got \(result)")
            return
        }

        #expect(options.challenge == ChallengeID("Y2hhbGxlbmdlLWJ5dGVz"))
        #expect(options.rpID == "login.example.test")
        #expect(options.userVerification == .required)
        #expect(options.timeout == Timeout(milliseconds: 120000))
        #expect(options.allowCredentials?.count == 1)
        #expect(options.allowCredentials?.first?.id == "Y3JlZGVudGlhbC1pZA")
        #expect(options.allowCredentials?.first?.type == .publicKey)
        #expect(options.allowCredentials?.first?.transports == [.internal, .hybrid, .smartCard])
    }

    @Test func `Options success accepts padded Base64url assertion options`() throws {
        let challenge = paddedBase64URL("a")
        let credentialID = paddedBase64URL("credential")

        let result = try makeOptionsCall().mapHttpSuccess(
            success(
                code: 201,
                path: "passkeys/assertion/options",
                body: """
                    {
                      "challenge": "\(challenge)",
                      "rpId": "login.example.test",
                      "allowCredentials": [
                        {"id": "\(credentialID)", "type": "public-key"}
                      ]
                    }
                    """
            )
        )

        let options = try requireSuccess(result)

        #expect(options.challenge == ChallengeID(challenge))
        #expect(options.rpID == "login.example.test")
        #expect(options.allowCredentials?.first?.id == credentialID)
        #expect(options.allowCredentials?.first?.type == .publicKey)
    }

    @Test(arguments: AssertionOptionsMalformedBase64URLField.allCases)
    fileprivate func `Malformed Base64url assertion option fields map to unexpected`(
        _ field: AssertionOptionsMalformedBase64URLField
    ) throws {
        let result = try makeOptionsCall().mapHttpSuccess(
            success(
                code: 201,
                path: "passkeys/assertion/options",
                body: field.responseBody
            )
        )

        try assertOptionsUnexpectedResponseError(try requireFailure(result), statusCode: 201)
    }

    @Test func `Options HTTP errors map start failure contracts`() throws {
        assertOptionsInvalidLoginID(
            try makeOptionsCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "passkeys/assertion/options",
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
                    path: "passkeys/assertion/options",
                    body: #"{"errorCode":"forbidden","message":"Passkey assertion is forbidden"}"#
                )
            )
        )
        assertOptionsUserNotFound(
            try makeOptionsCall().mapHttpError(
                httpError(
                    statusCode: 404,
                    path: "passkeys/assertion/options",
                    body: #"{"errorCode":"user_not_found","message":"Passkey assertion user not found"}"#
                )
            )
        )
        assertOptionsProviderFailed(
            try makeOptionsCall().mapHttpError(
                httpError(
                    statusCode: 424,
                    path: "passkeys/assertion/options",
                    body: """
                        {
                          "errorCode": "integration_error",
                          "message": "Passkey provider failed",
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
                    path: "passkeys/assertion/options",
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
                        code: 201,
                        path: "passkeys/assertion/options",
                        body: assertionOptionsBody(challenge: "YXNzZXJ0aW9uLXBhcmFtcy1jaGFsbGVuZ2U")
                    )
                ),
                .success(success(code: 200, path: "passkeys/assertion/result", body: #"{"accessToken":"verified-access-token"}"#)),
                .success(success(code: 204, path: "passkeys/assertion/cancel", body: "")),
            ]
        )
        let api = makeAPI(network: network, context: nil)

        let startResult = await api.start(
            params: PasskeyAssertionAPIParams(
                loginID: LoginID(id: "params@example.test", type: .email),
                accessToken: AccessToken(token: "params-access-token"),
                traceParent: traceParent
            )
        )
        let controller = try #require(startResult.getOrNil())

        #expect(controller.assertionOptions.challenge == ChallengeID("YXNzZXJ0aW9uLXBhcmFtcy1jaGFsbGVuZ2U"))
        assertAssertionStartRequest(
            try #require(await network.request(at: 0)).buildURLRequest(),
            loginID: "params@example.test",
            accessToken: "params-access-token",
            traceParent: traceParent
        )

        guard case .success(let accessToken) = await controller.verify(assertionResult: makeAssertionResult()) else {
            Issue.record("Expected assertion verify success")
            return
        }
        #expect(accessToken == AccessToken(token: "verified-access-token"))

        guard case .success = await controller.cancel(reason: .moveToOtherChallenge) else {
            Issue.record("Expected assertion cancel success")
            return
        }

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 3)
        assertAssertionVerifyRequest(
            requests[1].buildURLRequest(),
            accessToken: "params-access-token",
            traceParent: traceParent
        )
        assertAssertionCancelRequest(
            requests[2].buildURLRequest(),
            challenge: "YXNzZXJ0aW9uLXBhcmFtcy1jaGFsbGVuZ2U",
            reason: "moveToOtherChallenge",
            traceParent: traceParent
        )
    }

    @Test func `Start uses context login ID and access token fallbacks`() async throws {
        let loginIDNetwork = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 201,
                        path: "passkeys/assertion/options",
                        body: assertionOptionsBody(challenge: "YXNzZXJ0aW9uLWNvbnRleHQtbG9naW4taWQ")
                    )
                )
            ]
        )
        let loginIDAPI = makeAPI(
            network: loginIDNetwork,
            context: makeContext(authz: .start("context@example.test", type: .email))
        )

        guard case .success = await loginIDAPI.start(params: nil) else {
            Issue.record("Expected assertion context login ID start success")
            return
        }
        assertAssertionStartRequest(
            try #require(await loginIDNetwork.request(at: 0)).buildURLRequest(),
            loginID: "context@example.test",
            accessToken: nil,
            traceParent: nil
        )

        let accessTokenNetwork = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 201,
                        path: "passkeys/assertion/options",
                        body: assertionOptionsBody(challenge: "YXNzZXJ0aW9uLWNvbnRleHQtdG9rZW4")
                    )
                ),
                .success(success(code: 200, path: "passkeys/assertion/result", body: #"{"accessToken":"verified-context-token"}"#)),
            ]
        )
        let accessTokenAPI = makeAPI(
            network: accessTokenNetwork,
            context: makeContext(authz: .fromToken(AccessToken(token: "context-access-token")))
        )
        let controller = try #require((await accessTokenAPI.start(params: nil)).getOrNil())
        guard case .success = await controller.verify(assertionResult: makeAssertionResult()) else {
            Issue.record("Expected assertion context access-token verify success")
            return
        }

        let requests = await accessTokenNetwork.requestsSnapshot()
        #expect(requests.count == 2)
        assertAssertionStartRequest(
            requests[0].buildURLRequest(),
            loginID: nil,
            accessToken: "context-access-token",
            traceParent: nil
        )
        assertAssertionVerifyRequest(
            requests[1].buildURLRequest(),
            accessToken: "context-access-token",
            traceParent: requests[0].buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        )
    }

    @Test func `Caller cancellation does not send server-side cancel`() async throws {
        let startNetwork = APIRecordingNetwork(suspendingAfter: [])
        let startAPI = makeAPI(network: startNetwork, context: nil)
        let startTask = Task {
            await startAPI.start(
                params: PasskeyAssertionAPIParams(
                    loginID: LoginID(id: "cancel-start@example.test", type: .email),
                    accessToken: nil,
                    traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00"
                )
            )
        }
        await confirmation("assertion start request was sent before task cancellation") { requestSent in
            await startNetwork.waitForRequestCount(1)
            requestSent()
            startTask.cancel()
        }
        guard case .canceled = await startTask.value else {
            Issue.record("Expected assertion start task cancellation")
            return
        }
        #expect(await startNetwork.requestPaths() == ["/api/passkeys/assertion/options"])

        let verifyNetwork = APIRecordingNetwork(suspendingAfter: [])
        let controller = PasskeyAssertionAPIControllerImpl(
            apiBaseURL: baseURL,
            network: verifyNetwork,
            coder: coder,
            assertionOptions: AssertionOptions(challenge: ChallengeID("controller-cancel-challenge"), rpID: "login.example.test"),
            accessToken: AccessToken(token: "controller-access-token"),
            traceParent: "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-01",
            interceptor: nil
        )
        let verifyTask = Task { await controller.verify(assertionResult: makeAssertionResult()) }
        await confirmation("assertion verify request was sent before task cancellation") { requestSent in
            await verifyNetwork.waitForRequestCount(1)
            requestSent()
            verifyTask.cancel()
        }
        guard case .canceled = await verifyTask.value else {
            Issue.record("Expected assertion verify task cancellation")
            return
        }
        #expect(await verifyNetwork.requestPaths() == ["/api/passkeys/assertion/result"])
    }

    @Test func `Verify request builds assertion result endpoint body and headers`() throws {
        let call = try PasskeyAssertionResultAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            assertionResult: AssertionResult(
                id: "credential-id",
                type: .publicKey,
                response: .init(
                    clientDataJSON: "client-data-json",
                    authenticatorData: "authenticator-data",
                    signature: "assertion-signature",
                    userHandle: nil
                ),
                authenticatorAttachment: nil
            ),
            accessToken: AccessToken(token: "verify-access-token"),
            traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)
        let response = try #require(body["response"] as? [String: Any])

        #expect(request.url == baseURL.appendingPathComponent("passkeys/assertion/result"))
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
        #expect(response["authenticatorData"] as? String == "authenticator-data")
        #expect(response["signature"] as? String == "assertion-signature")
        #expect(response["userHandle"] == nil)
    }

    @Test func `Verify success maps access token response`() throws {
        let result = try makeVerifyCall().mapHttpSuccess(
            success(
                code: 200,
                path: "passkeys/assertion/result",
                body: #"{"accessToken":"ownid-access-token"}"#
            )
        )

        guard case .success(let accessToken) = result else {
            Issue.record("Expected assertion verify success, got \(result)")
            return
        }
        #expect(accessToken == AccessToken(token: "ownid-access-token"))
    }

    @Test func `Cancel request builds assertion cancel endpoint body and maps no-content success`() throws {
        let call = try PasskeyAssertionCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challenge: ChallengeID("assertion-challenge"),
            reason: .moveToOtherChallenge,
            traceParent: "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-00"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)

        #expect(request.url == baseURL.appendingPathComponent("passkeys/assertion/cancel"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == nil)
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-00"
        )
        #expect(body["challenge"] as? String == "assertion-challenge")
        #expect(body["reason"] as? String == "moveToOtherChallenge")
        #expect(body.keys.sorted() == ["challenge", "reason"])

        guard case .success = call.mapHttpSuccess(success(code: 204, path: "passkeys/assertion/cancel", body: "")) else {
            Issue.record("Expected assertion cancel success")
            return
        }
        guard
            case .failure(.unexpected(let errorCode, _, _)) =
                call.mapHttpSuccess(success(code: 200, path: "passkeys/assertion/cancel", body: ""))
        else {
            Issue.record("Expected assertion cancel unexpected failure for non-204 success")
            return
        }
        #expect(errorCode == .unknown)
    }

    @Test func `Bad challenge HTTP errors map to verify and cancel failure contracts`() throws {
        let failure = httpError(
            statusCode: 400,
            path: "passkeys/assertion/result",
            body: """
                {
                  "errorCode": "maximum_attempts_reached",
                  "message": "Maximum attempts reached",
                  "challengeId": "expired-challenge"
                }
                """
        )

        assertVerifyMaximumAttemptsReached(try makeVerifyCall().mapHttpError(failure))
        assertCancelMaximumAttemptsReached(
            try makeCancelCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "passkeys/assertion/cancel",
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
    }

    private func makeOptionsCall() throws -> PasskeyAssertionOptionsAPICall {
        try PasskeyAssertionOptionsAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: nil,
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeAPI(network: any NetworkProtocol, context: Context?) -> PasskeyAssertionAPIImpl {
        PasskeyAssertionAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: context,
            loginIDValidator: nil,
            interceptor: nil
        )
    }

    private func makeContext(authz: Authz) -> Context {
        var builder = Context.Builder()
        builder.authz = authz
        return builder.build(scopeName: "test")
    }

    private func makeVerifyCall() throws -> PasskeyAssertionResultAPICall {
        try PasskeyAssertionResultAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            assertionResult: AssertionResult(
                id: "credential-id",
                type: .publicKey,
                response: .init(
                    clientDataJSON: "client-data-json",
                    authenticatorData: "authenticator-data",
                    signature: "assertion-signature",
                    userHandle: "user-handle"
                ),
                authenticatorAttachment: .crossPlatform
            ),
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeAssertionResult() -> AssertionResult {
        AssertionResult(
            id: "credential-id",
            type: .publicKey,
            response: .init(
                clientDataJSON: "client-data-json",
                authenticatorData: "authenticator-data",
                signature: "assertion-signature",
                userHandle: "user-handle"
            ),
            authenticatorAttachment: .crossPlatform
        )
    }

    private func makeCancelCall() throws -> PasskeyAssertionCancelAPICall {
        try PasskeyAssertionCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challenge: ChallengeID("assertion-challenge"),
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

    private func assertionOptionsBody(challenge: String) -> String {
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

    private func assertAssertionStartRequest(
        _ request: URLRequest,
        loginID: String?,
        accessToken: String?,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("passkeys/assertion/options"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        if let traceParent {
            #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)
        } else {
            #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) != nil)
        }

        do {
            if let loginID {
                let body = try bodyObject(from: request)
                let bodyLoginID = try #require(body["loginId"] as? [String: Any])
                #expect(bodyLoginID["id"] as? String == loginID)
                #expect(bodyLoginID["type"] as? String == "Email")
                #expect(body.keys.sorted() == ["loginId"])
            } else {
                let body = try bodyObject(from: request)
                #expect(body.isEmpty)
            }
        } catch {
            Issue.record("Failed to decode assertion start body: \(error)")
        }
    }

    private func assertAssertionVerifyRequest(
        _ request: URLRequest,
        accessToken: String?,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("passkeys/assertion/result"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            let body = try bodyObject(from: request)
            let response = try #require(body["response"] as? [String: Any])
            #expect(body["id"] as? String == "credential-id")
            #expect(body["type"] as? String == "public-key")
            #expect(response["signature"] as? String == "assertion-signature")
        } catch {
            Issue.record("Failed to decode assertion verify body: \(error)")
        }
    }

    private func assertAssertionCancelRequest(
        _ request: URLRequest,
        challenge: String,
        reason: String,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("passkeys/assertion/cancel"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == nil)
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            let body = try bodyObject(from: request)
            #expect(body["challenge"] as? String == challenge)
            #expect(body["reason"] as? String == reason)
            #expect(body.keys.sorted() == ["challenge", "reason"])
        } catch {
            Issue.record("Failed to decode assertion cancel body: \(error)")
        }
    }

    private func assertOptionsInvalidLoginID(
        _ failure: PasskeyAssertionStartAPIFailure,
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
        _ failure: PasskeyAssertionStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected options forbidden failure, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "Passkey assertion is forbidden")
    }

    private func assertOptionsUserNotFound(
        _ failure: PasskeyAssertionStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .userNotFound(let errorCode, let message) = failure else {
            Issue.record("Expected options user not found failure, got \(failure)")
            return
        }
        #expect(errorCode == .userNotFound)
        #expect(message == "Passkey assertion user not found")
    }

    private func assertOptionsProviderFailed(
        _ failure: PasskeyAssertionStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected options provider failed failure, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Passkey provider failed")
        #expect(scope == .data)
    }

    private func assertOptionsMaximumChallenges(
        _ failure: PasskeyAssertionStartAPIFailure,
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
        _ failure: PasskeyAssertionStartAPIFailure,
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

    private func assertVerifyMaximumAttemptsReached(
        _ failure: PasskeyAssertionVerifyAPIFailure,
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

    private func assertCancelMaximumAttemptsReached(
        _ failure: PasskeyAssertionCancelAPIFailure,
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
}

private enum AssertionOptionsMalformedBase64URLField: CaseIterable, Sendable, CustomTestStringConvertible {
    case challenge
    case allowCredentialID

    var testDescription: String {
        switch self {
        case .challenge: return "challenge"
        case .allowCredentialID: return "allowCredentials.id"
        }
    }

    var responseBody: String {
        switch self {
        case .challenge:
            return """
                {
                  "challenge": "YQ=",
                  "rpId": "login.example.test",
                  "allowCredentials": [
                    {"id": "\(paddedBase64URL("credential"))", "type": "public-key"}
                  ]
                }
                """
        case .allowCredentialID:
            return """
                {
                  "challenge": "\(paddedBase64URL("a"))",
                  "rpId": "login.example.test",
                  "allowCredentials": [
                    {"id": "YQ=", "type": "public-key"}
                  ]
                }
                """
        }
    }
}
