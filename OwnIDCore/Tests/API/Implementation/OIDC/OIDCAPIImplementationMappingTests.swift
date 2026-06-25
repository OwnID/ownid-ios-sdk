import Foundation
import Testing

@testable import OwnIDCore

struct OIDCAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Start request builds provider endpoint body and headers`() throws {
        let call = try OIDCStartAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            provider: .google,
            oauthResponseType: .code,
            accessToken: AccessToken(token: "session-access-token"),
            loginIDHint: "user@example.test",
            redirectURI: "ownid://callback",
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)

        #expect(request.url == baseURL.appendingPathComponent("oidc/idp/start/google"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer session-access-token")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        #expect(body["loginIdHint"] as? String == "user@example.test")
        #expect(body["oauthResponseType"] as? String == "code")
        #expect(body["redirectUri"] as? String == "ownid://callback")
        #expect(body.keys.sorted() == ["loginIdHint", "oauthResponseType", "redirectUri"])
    }

    @Test func `Start implementation defaults nil provider to Apple and uses explicit Google provider`() async throws {
        let appleNetwork = APIRecordingNetwork(
            response: .success(
                success(
                    code: 201,
                    body: """
                        {
                          "challengeId": "apple-challenge",
                          "timeout": 30000,
                          "clientId": "apple-client-id"
                        }
                        """
                )
            )
        )
        let appleAPI = OIDCAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: appleNetwork,
            coder: coder,
            context: nil,
            interceptor: nil
        )
        guard case .success = await appleAPI.start(params: OIDCAPIParams(provider: nil)) else {
            Issue.record("Expected default Apple OIDC start success")
            return
        }
        let appleRequestURLs = await appleNetwork.requestURLs()
        #expect(appleRequestURLs == [baseURL.appendingPathComponent("oidc/idp/start/apple")])
        let appleRequests = await appleNetwork.requestsSnapshot()
        #expect(appleRequests.count == 1)
        let appleTraceParent = appleRequests[0].buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        #expect(appleTraceParent?.isEmpty == false)
        assertStartRequest(
            appleRequests[0].buildURLRequest(),
            provider: .apple,
            oauthResponseType: .idToken,
            accessToken: nil,
            traceParent: appleTraceParent
        )

        let googleNetwork = APIRecordingNetwork(
            response: .success(
                success(
                    code: 201,
                    body: """
                        {
                          "challengeId": "google-challenge",
                          "timeout": 30000,
                          "clientId": "google-client-id"
                        }
                        """
                )
            )
        )
        let googleAPI = OIDCAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: googleNetwork,
            coder: coder,
            context: nil,
            interceptor: nil
        )
        guard case .success = await googleAPI.start(params: OIDCAPIParams(provider: .google)) else {
            Issue.record("Expected explicit Google OIDC start success")
            return
        }
        let googleRequestURLs = await googleNetwork.requestURLs()
        #expect(googleRequestURLs == [baseURL.appendingPathComponent("oidc/idp/start/google")])
        let googleRequests = await googleNetwork.requestsSnapshot()
        #expect(googleRequests.count == 1)
        let googleTraceParent = googleRequests[0].buildURLRequest().value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
        #expect(googleTraceParent?.isEmpty == false)
        assertStartRequest(
            googleRequests[0].buildURLRequest(),
            provider: .google,
            oauthResponseType: .idToken,
            accessToken: nil,
            traceParent: googleTraceParent
        )
    }

    @Test func `Start returns controller capturing context traceparent and response type snapshot`() async throws {
        let initialTraceParent = "00-55555555555555555555555555555555-6666666666666666-01"
        var context = context(accessToken: "context-access-token")
        var params = OIDCAPIParams(provider: .google, oauthResponseType: .code, accessToken: nil, traceParent: initialTraceParent)
        let network = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 201,
                        body: """
                            {
                              "challengeId": "snapshot-challenge",
                              "timeout": 45000,
                              "clientId": "snapshot-client-id",
                              "challengeUrl": "https://provider.example.test/snapshot"
                            }
                            """
                    )
                ),
                .success(
                    success(
                        code: 200,
                        body: """
                            {
                              "accessToken": "ownid-snapshot-token",
                              "loginId": {"id": "snapshot@example.test", "type": "Email"},
                              "userInfo": {"email": "snapshot@example.test"},
                              "provider": "Google"
                            }
                            """
                    )
                ),
            ]
        )
        let api = OIDCAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: context,
            interceptor: nil
        )

        let startResult = await api.start(params: params)

        guard case .success(let controller) = startResult else {
            Issue.record("Expected OIDC start success, got \(startResult)")
            return
        }
        #expect(controller.challenge.challengeID == ChallengeID("snapshot-challenge"))
        #expect(controller.challenge.timeout == Timeout(milliseconds: 45000))
        #expect(controller.challenge.clientID == "snapshot-client-id")
        #expect(controller.challenge.challengeURL == "https://provider.example.test/snapshot")

        context = self.context(accessToken: "later-context-access-token")
        params = OIDCAPIParams(
            provider: .apple,
            oauthResponseType: .idToken,
            accessToken: AccessToken(token: "later-param-access-token"),
            traceParent: "00-77777777777777777777777777777777-8888888888888888-00"
        )
        #expect(context.accessToken == AccessToken(token: "later-context-access-token"))
        #expect(params.provider == .apple)
        #expect(params.oauthResponseType == .idToken)
        #expect(params.accessToken == AccessToken(token: "later-param-access-token"))

        let completeResult = await controller.completeWithCode(code: "provider-code")

        guard case .success(let completeResponse) = completeResult else {
            Issue.record("Expected captured code response type to complete successfully, got \(completeResult)")
            return
        }
        #expect(completeResponse.accessToken == AccessToken(token: "ownid-snapshot-token"))
        #expect(completeResponse.loginID == LoginID(id: "snapshot@example.test", type: .email))
        #expect(completeResponse.provider == .google)

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 2)
        assertStartRequest(
            requests[0].buildURLRequest(),
            provider: .google,
            oauthResponseType: .code,
            accessToken: "context-access-token",
            traceParent: initialTraceParent
        )
        assertCompleteRequest(
            requests[1].buildURLRequest(),
            challengeID: "snapshot-challenge",
            credentialKey: "code",
            credentialValue: "provider-code",
            accessToken: "context-access-token",
            traceParent: initialTraceParent
        )
    }

    @Test func `Start maps created challenge response`() throws {
        let call = try makeStartCall()
        let result = call.mapHttpSuccess(
            success(
                code: 201,
                body: """
                    {
                      "challengeId": "oidc-challenge-1",
                      "timeout": 30000,
                      "clientId": "provider-client-id",
                      "challengeUrl": "https://provider.example.test/challenge"
                    }
                    """
            )
        )

        guard case .success(let challenge) = result else {
            Issue.record("Expected OIDC start success, got \(result)")
            return
        }
        #expect(challenge.challengeID == ChallengeID("oidc-challenge-1"))
        #expect(challenge.timeout == Timeout(milliseconds: 30000))
        #expect(challenge.clientID == "provider-client-id")
        #expect(challenge.challengeURL == "https://provider.example.test/challenge")
    }

    @Test func `Start maps HTTP error branches`() throws {
        assertStartInvalidArgument(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    body: #"{"errorCode":"invalid_argument","message":"Provider is invalid"}"#
                )
            )
        )
        assertStartForbidden(
            try makeStartCall().mapHttpError(
                httpError(statusCode: 403, body: #"{"errorCode":"forbidden","message":"OIDC start forbidden"}"#)
            )
        )
        assertStartMissingProvider(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 424,
                    body: """
                        {
                          "errorCode": "missing_capability_provider",
                          "message": "OIDC provider is missing",
                          "capability": "oidc",
                          "scope": "session"
                        }
                        """
                )
            )
        )
        assertStartMaximumChallenges(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 429,
                    body: #"{"errorCode":"maximum_challenges_reached","message":"Too many active OIDC challenges"}"#
                )
            )
        )
    }

    @Test func `Complete token and code requests build endpoint bodies and headers`() throws {
        let tokenCall = try OIDCCompleteIDTokenAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("token-challenge"),
            idToken: "provider-id-token",
            accessToken: AccessToken(token: "token-access-token"),
            traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
        )
        assertCompleteRequest(
            tokenCall.request.buildURLRequest(),
            challengeID: "token-challenge",
            credentialKey: "idToken",
            credentialValue: "provider-id-token",
            accessToken: "token-access-token",
            traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
        )

        let codeCall = try OIDCCompleteCodeAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("code-challenge"),
            code: "provider-code",
            accessToken: nil,
            traceParent: nil
        )
        assertCompleteRequest(
            codeCall.request.buildURLRequest(),
            challengeID: "code-challenge",
            credentialKey: "code",
            credentialValue: "provider-code",
            accessToken: nil,
            traceParent: nil
        )
    }

    @Test func `Complete maps access token with user info response`() throws {
        let result = try makeCompleteTokenCall().mapHttpSuccess(
            success(
                code: 200,
                body: """
                    {
                      "accessToken": "ownid-access-token",
                      "loginId": {"id": "user@example.test", "type": "Email"},
                      "userInfo": {"email": "user@example.test", "sub": "provider-user-id"},
                      "provider": "Google"
                    }
                    """
            )
        )

        guard case .success(let response) = result else {
            Issue.record("Expected OIDC complete success, got \(result)")
            return
        }
        #expect(response.accessToken == AccessToken(token: "ownid-access-token"))
        #expect(response.loginID == LoginID(id: "user@example.test", type: .email))
        #expect(response.userInfo == ["email": "user@example.test", "sub": "provider-user-id"])
        #expect(response.provider == .google)
    }

    @Test func `Complete token and code map HTTP error branches`() throws {
        let badRequest = httpError(
            statusCode: 400,
            body: """
                {
                  "errorCode": "maximum_attempts_reached",
                  "message": "OIDC attempts exhausted",
                  "challengeId": "complete-challenge"
                }
                """
        )
        assertCompleteMaximumAttemptsReached(try makeCompleteTokenCall().mapHttpError(badRequest))
        assertCompleteMaximumAttemptsReached(try makeCompleteCodeCall().mapHttpError(badRequest))

        let forbidden = httpError(statusCode: 403, body: #"{"errorCode":"forbidden","message":"OIDC complete forbidden"}"#)
        assertCompleteForbidden(try makeCompleteTokenCall().mapHttpError(forbidden))
        assertCompleteForbidden(try makeCompleteCodeCall().mapHttpError(forbidden))

        let failedDependency = httpError(
            statusCode: 424,
            body: """
                {
                  "errorCode": "integration_error",
                  "message": "OIDC provider failed",
                  "scope": "session"
                }
                """
        )
        assertCompleteProviderFailed(try makeCompleteTokenCall().mapHttpError(failedDependency))
        assertCompleteProviderFailed(try makeCompleteCodeCall().mapHttpError(failedDependency))
    }

    @Test func `Controller complete with token executes token completion call`() async throws {
        let network = APIRecordingNetwork(
            response: .success(
                success(
                    code: 200,
                    body: """
                        {
                          "accessToken": "ownid-access-token",
                          "loginId": {"id": "user@example.test", "type": "Email"},
                          "userInfo": {"email": "user@example.test"},
                          "provider": "Apple"
                        }
                        """
                )
            )
        )
        let controller = makeController(
            network: network,
            expectedResponseType: .idToken,
            accessToken: AccessToken(token: "controller-access-token"),
            traceParent: "00-11111111111111111111111111111111-2222222222222222-01"
        )

        let result = await controller.completeWithToken(idToken: "provider-id-token")

        guard case .success(let response) = result else {
            Issue.record("Expected controller token completion success, got \(result)")
            return
        }
        #expect(response.accessToken == AccessToken(token: "ownid-access-token"))
        #expect(response.loginID == LoginID(id: "user@example.test", type: .email))
        #expect(response.provider == .apple)

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 1)
        assertCompleteRequest(
            requests[0].buildURLRequest(),
            challengeID: "controller-challenge",
            credentialKey: "idToken",
            credentialValue: "provider-id-token",
            accessToken: "controller-access-token",
            traceParent: "00-11111111111111111111111111111111-2222222222222222-01"
        )
    }

    @Test func `Controller complete with code executes code completion call`() async throws {
        let network = APIRecordingNetwork(
            response: .success(
                success(
                    code: 200,
                    body: """
                        {
                          "accessToken": "ownid-code-access-token",
                          "loginId": {"id": "user@example.test", "type": "Email"},
                          "userInfo": {"email": "user@example.test"},
                          "provider": "Google"
                        }
                        """
                )
            )
        )
        let controller = makeController(
            network: network,
            expectedResponseType: .code,
            accessToken: nil,
            traceParent: nil
        )

        let result = await controller.completeWithCode(code: "provider-code")

        guard case .success(let response) = result else {
            Issue.record("Expected controller code completion success, got \(result)")
            return
        }
        #expect(response.accessToken == AccessToken(token: "ownid-code-access-token"))
        #expect(response.provider == .google)

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 1)
        assertCompleteRequest(
            requests[0].buildURLRequest(),
            challengeID: "controller-challenge",
            credentialKey: "code",
            credentialValue: "provider-code",
            accessToken: nil,
            traceParent: nil
        )
    }

    @Test func `Controller completion rejects mismatched response type without network call`() async throws {
        let tokenNetwork = APIRecordingNetwork(response: .success(success(code: 200, body: "{}")))
        let tokenController = makeController(network: tokenNetwork, expectedResponseType: .code)
        assertCompleteInvalidArgument(await tokenController.completeWithToken(idToken: "provider-id-token"))
        let tokenRequestURLs = await tokenNetwork.requestURLs()
        #expect(tokenRequestURLs == [])

        let codeNetwork = APIRecordingNetwork(response: .success(success(code: 200, body: "{}")))
        let codeController = makeController(network: codeNetwork, expectedResponseType: .idToken)
        assertCompleteInvalidArgument(await codeController.completeWithCode(code: "provider-code"))
        let codeRequestURLs = await codeNetwork.requestURLs()
        #expect(codeRequestURLs == [])
    }

    @Test func `Caller task cancellation during start does not request server-side cancel`() async throws {
        let network = APIRecordingNetwork(suspendingAfter: [])
        let api = OIDCAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: nil,
            interceptor: nil
        )

        let task = Task {
            await api.start(params: OIDCAPIParams(provider: .google, oauthResponseType: .code))
        }

        await confirmation("OIDC start request was sent before task cancellation") { requestSent in
            await network.waitForRequestCount(1)
            requestSent()
            task.cancel()
        }

        guard case .canceled = await task.value else {
            Issue.record("Expected canceled start result")
            return
        }
        let requests = await network.requestsSnapshot()
        #expect(requests.map(\.url) == [baseURL.appendingPathComponent("oidc/idp/start/google")])
        assertNoCancelRequest(requests)
    }

    @Test func `Caller task cancellation during controller completion does not request server-side cancel`() async throws {
        let network = APIRecordingNetwork(
            suspendingAfter: [
                .success(
                    success(
                        code: 201,
                        body: """
                            {
                              "challengeId": "completion-cancel-challenge",
                              "timeout": 30000,
                              "clientId": "completion-cancel-client-id"
                            }
                            """
                    )
                )
            ]
        )
        let api = OIDCAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: nil,
            interceptor: nil
        )
        let startResult = await api.start(params: OIDCAPIParams(provider: .google, oauthResponseType: .code))
        guard case .success(let controller) = startResult else {
            Issue.record("Expected OIDC start success, got \(startResult)")
            return
        }

        let task = Task {
            await controller.completeWithCode(code: "provider-code")
        }

        await confirmation("OIDC completion request was sent before task cancellation") { requestSent in
            await network.waitForRequestCount(2)
            requestSent()
            task.cancel()
        }

        guard case .canceled = await task.value else {
            Issue.record("Expected canceled completion result")
            return
        }
        let requests = await network.requestsSnapshot()
        #expect(
            requests.map(\.url) == [
                baseURL.appendingPathComponent("oidc/idp/start/google"),
                baseURL.appendingPathComponent("oidc/idp/complete"),
            ]
        )
        assertNoCancelRequest(requests)
    }

    @Test func `Cancel request builds body and maps no-content success`() throws {
        let call = try OIDCCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("cancel-challenge"),
            reason: .moveToOtherChallenge,
            accessToken: AccessToken(token: "cancel-access-token"),
            traceParent: "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-00"
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)

        #expect(request.url == baseURL.appendingPathComponent("oidc/idp/cancel"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer cancel-access-token")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-00"
        )
        #expect(body["challengeId"] as? String == "cancel-challenge")
        #expect(body["reason"] as? String == "moveToOtherChallenge")
        #expect(body.keys.sorted() == ["challengeId", "reason"])

        guard case .success = call.mapHttpSuccess(success(code: 204, body: "")) else {
            Issue.record("Expected OIDC cancel success")
            return
        }
        guard case .failure(.unexpected(let errorCode, _, _)) = call.mapHttpSuccess(success(code: 200, body: "")) else {
            Issue.record("Expected OIDC cancel unexpected failure for non-204 success")
            return
        }
        #expect(errorCode == .unknown)
    }

    @Test func `Cancel maps HTTP error branches`() throws {
        assertCancelInvalidChallenge(
            try makeCancelCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    body: """
                        {
                          "errorCode": "invalid_challenge",
                          "message": "OIDC challenge is invalid",
                          "challengeId": "cancel-challenge"
                        }
                        """
                )
            )
        )
        assertCancelForbidden(
            try makeCancelCall().mapHttpError(
                httpError(statusCode: 403, body: #"{"errorCode":"forbidden","message":"OIDC cancel forbidden"}"#)
            )
        )
    }

    @Test func `Controller cancel executes cancel call`() async throws {
        let network = APIRecordingNetwork(response: .success(success(code: 204, body: "")))
        let controller = makeController(
            network: network,
            expectedResponseType: .idToken,
            accessToken: AccessToken(token: "cancel-access-token"),
            traceParent: "00-33333333333333333333333333333333-4444444444444444-00"
        )

        let result = await controller.cancel(reason: .moveToOtherChallenge)

        guard case .success = result else {
            Issue.record("Expected controller cancel success, got \(result)")
            return
        }

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 1)

        let request = requests[0].buildURLRequest()
        let body = try bodyObject(from: request)
        #expect(request.url == baseURL.appendingPathComponent("oidc/idp/cancel"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer cancel-access-token")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-33333333333333333333333333333333-4444444444444444-00"
        )
        #expect(body["challengeId"] as? String == "controller-challenge")
        #expect(body["reason"] as? String == "moveToOtherChallenge")
        #expect(body.keys.sorted() == ["challengeId", "reason"])
    }

    private func makeStartCall() throws -> OIDCStartAPICall {
        try OIDCStartAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            provider: .apple,
            oauthResponseType: .idToken,
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeCompleteTokenCall() throws -> OIDCCompleteIDTokenAPICall {
        try OIDCCompleteIDTokenAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("complete-challenge"),
            idToken: "provider-id-token",
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeCompleteCodeCall() throws -> OIDCCompleteCodeAPICall {
        try OIDCCompleteCodeAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("complete-challenge"),
            code: "provider-code",
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeCancelCall() throws -> OIDCCancelAPICall {
        try OIDCCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("cancel-challenge"),
            reason: .timeout,
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeController(
        network: any NetworkProtocol,
        expectedResponseType: OAuthResponseType,
        accessToken: AccessToken? = nil,
        traceParent: String? = nil
    ) -> OIDCAPIControllerImpl {
        OIDCAPIControllerImpl(
            apiBaseURL: baseURL,
            coder: coder,
            network: network,
            challenge: SocialChallenge(
                challengeID: ChallengeID("controller-challenge"),
                timeout: Timeout(milliseconds: 30000),
                clientID: "provider-client-id",
                challengeURL: "https://provider.example.test/challenge"
            ),
            accessToken: accessToken,
            traceParent: traceParent,
            expectedResponseType: expectedResponseType,
            interceptor: nil
        )
    }

    private func success(code: Int, body: String) -> NetworkResponse.Success {
        NetworkResponse.Success(url: baseURL, code: code, headers: [:], body: body)
    }

    private func httpError(statusCode: Int, body: String) -> NetworkResponse.Fail.HttpError {
        NetworkResponse.Fail.HttpError(url: baseURL, statusCode: statusCode, headers: [:], body: body)
    }

    private func context(accessToken: String) -> Context {
        var builder = Context.Builder()
        builder.authz = .fromToken(accessToken)
        return builder.build(scopeName: "oidc-api-tests")
    }

    private func assertStartRequest(
        _ request: URLRequest,
        provider: SocialProviderID,
        oauthResponseType: OAuthResponseType,
        accessToken: String?,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("oidc/idp/start").appendingPathComponent(provider.rawValue.lowercased()))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            let body = try bodyObject(from: request)
            let expectedResponseType =
                switch oauthResponseType {
                case .code: "code"
                case .idToken: "id_token"
                }
            #expect(body["oauthResponseType"] as? String == expectedResponseType)
            #expect(body.keys.sorted() == ["oauthResponseType"])
        } catch {
            Issue.record("Failed to decode request body: \(error)")
        }
    }

    private func assertCompleteRequest(
        _ request: URLRequest,
        challengeID: String,
        credentialKey: String,
        credentialValue: String,
        accessToken: String?,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent("oidc/idp/complete"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            let body = try bodyObject(from: request)
            #expect(body["challengeId"] as? String == challengeID)
            #expect(body[credentialKey] as? String == credentialValue)
            #expect(body.keys.sorted() == ["challengeId", credentialKey].sorted())
        } catch {
            Issue.record("Failed to decode request body: \(error)")
        }
    }

    private func assertNoCancelRequest(
        _ requests: [NetworkRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(!requests.map(\.url).contains(baseURL.appendingPathComponent("oidc/idp/cancel")))
    }

    private func assertStartInvalidArgument(
        _ failure: OIDCStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidArgument(let errorCode, let message)) = failure else {
            Issue.record("Expected OIDC start invalid argument, got \(failure)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "Provider is invalid")
    }

    private func assertStartForbidden(
        _ failure: OIDCStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected OIDC start forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "OIDC start forbidden")
    }

    private func assertStartMissingProvider(
        _ failure: OIDCStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.missingProvider(let errorCode, let message, let capability, let scope)) = failure else {
            Issue.record("Expected OIDC start missing provider, got \(failure)")
            return
        }
        #expect(errorCode == .missingCapabilityProvider)
        #expect(message == "OIDC provider is missing")
        #expect(capability == "oidc")
        #expect(scope == .session)
    }

    private func assertStartMaximumChallenges(
        _ failure: OIDCStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .maximumChallengesReached(let errorCode, let message) = failure else {
            Issue.record("Expected OIDC start maximum challenges, got \(failure)")
            return
        }
        #expect(errorCode == .maximumChallengesReached)
        #expect(message == "Too many active OIDC challenges")
    }

    private func assertCompleteMaximumAttemptsReached(
        _ failure: OIDCCompleteAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.maximumAttemptsReached(let errorCode, let message, let challengeID)) = failure else {
            Issue.record("Expected OIDC complete maximum attempts, got \(failure)")
            return
        }
        #expect(errorCode == .maximumAttemptsReached)
        #expect(message == "OIDC attempts exhausted")
        #expect(challengeID == ChallengeID("complete-challenge"))
    }

    private func assertCompleteForbidden(
        _ failure: OIDCCompleteAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected OIDC complete forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "OIDC complete forbidden")
    }

    private func assertCompleteProviderFailed(
        _ failure: OIDCCompleteAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected OIDC complete provider failed, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "OIDC provider failed")
        #expect(scope == .session)
    }

    private func assertCompleteInvalidArgument(
        _ result: APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.invalidArgument(let errorCode, let message))) = result else {
            Issue.record("Expected OIDC complete invalid argument, got \(result)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(!(message.isEmpty))
    }

    private func assertCancelInvalidChallenge(
        _ failure: OIDCCancelAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidChallenge(let errorCode, let message, let challengeID)) = failure else {
            Issue.record("Expected OIDC cancel invalid challenge, got \(failure)")
            return
        }
        #expect(errorCode == .invalidChallenge)
        #expect(message == "OIDC challenge is invalid")
        #expect(challengeID == ChallengeID("cancel-challenge"))
    }

    private func assertCancelForbidden(
        _ failure: OIDCCancelAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected OIDC cancel forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "OIDC cancel forbidden")
    }
}
