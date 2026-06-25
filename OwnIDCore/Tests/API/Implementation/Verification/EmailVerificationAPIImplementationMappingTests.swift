import Foundation
import Testing

@testable import OwnIDCore

struct EmailVerificationAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Email verification start returns controller that reuses captured challenge token and trace`() async throws {
        let traceParent = "00-11111111111111111111111111111111-2222222222222222-01"
        let network = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 201,
                        path: "verifications/email/start",
                        body: """
                            {
                              "challengeId": "controller-challenge",
                              "resendPolicy": {"allow": true, "attempts": 4, "debounce": 2},
                              "timeout": 45000,
                              "attempts": 6,
                              "channel": {"channel": "u***@example.test", "id": "email-channel-id"},
                              "methods": {"otp": {"length": 6}, "magicLink": {}}
                            }
                            """
                    )
                ),
                .success(success(code: 200, path: "verifications/email/complete", body: #"{"accessToken":"verified-access-token"}"#)),
                .success(success(code: 204, path: "verifications/email/resend", body: "")),
                .success(success(code: 204, path: "verifications/email/cancel", body: "")),
            ]
        )
        let api = makeAPI(network: network, context: nil)

        let controller = try #require(
            await api.start(
                params: EmailVerificationAPIParams(
                    loginID: LoginID(id: "params@example.test", type: .email),
                    loginIDHintID: "params-hint",
                    accessToken: AccessToken(token: "captured-access-token"),
                    verificationMethods: [.otp],
                    magicLinkRedirectURL: nil,
                    traceParent: traceParent
                )
            ).getOrNil()
        )

        #expect(controller.challenge.challengeID == ChallengeID("controller-challenge"))
        #expect(controller.challenge.channel == OperationChannel(channel: "u***@example.test", id: "email-channel-id"))
        #expect((await controller.completeWithCode(code: "654321")).getOrNil() == .accessToken(AccessToken(token: "verified-access-token")))
        #expect((await controller.resend()).getOrNil() != nil)
        #expect((await controller.cancel(reason: .moveToOtherChallenge)).getOrNil() != nil)

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 4)
        assertRequest(
            requests[0].buildURLRequest(),
            path: "verifications/email/start",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            assertLoginID(body["loginId"], id: "params@example.test", type: "Email")
            #expect(body["loginIdHintId"] as? String == "params-hint")
            #expect(body["verificationMethods"] as? [String] == ["Otp"])
            #expect(body.keys.sorted() == ["loginId", "loginIdHintId", "verificationMethods"])
        }
        assertRequest(
            requests[1].buildURLRequest(),
            path: "verifications/email/complete",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "controller-challenge")
            #expect(body["code"] as? String == "654321")
            #expect(body.keys.sorted() == ["challengeId", "code"])
        }
        assertRequest(
            requests[2].buildURLRequest(),
            path: "verifications/email/resend",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "controller-challenge")
            #expect(body.keys.sorted() == ["challengeId"])
        }
        assertRequest(
            requests[3].buildURLRequest(),
            path: "verifications/email/cancel",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "controller-challenge")
            #expect(body["reason"] as? String == "moveToOtherChallenge")
            #expect(body.keys.sorted() == ["challengeId", "reason"])
        }
    }

    @Test func `Email verification start uses context login ID and access token fallbacks`() async throws {
        let loginIDContext = context(authz: .start(LoginID(id: "context@example.test", type: .email)))
        let loginIDNetwork = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "verifications/email/start", body: startBody(challengeID: "context-login-challenge")))
            ]
        )
        _ = await makeAPI(network: loginIDNetwork, context: loginIDContext).start(params: nil)
        let loginIDRequests = await loginIDNetwork.requestsSnapshot()
        let loginIDRequest = try #require(loginIDRequests.first?.buildURLRequest())
        let loginIDTraceParent = try #require(loginIDRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue))
        assertRequest(
            loginIDRequest,
            path: "verifications/email/start",
            accessToken: nil,
            traceParent: loginIDTraceParent
        ) { body in
            assertLoginID(body["loginId"], id: "context@example.test", type: "Email")
            #expect(body.keys.sorted() == ["loginId"])
        }

        let tokenContext = context(authz: .fromToken(AccessToken(token: "context-access-token")))
        let tokenNetwork = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "verifications/email/start", body: startBody(challengeID: "context-token-challenge")))
            ]
        )
        _ = await makeAPI(network: tokenNetwork, context: tokenContext).start(params: nil)
        let tokenRequests = await tokenNetwork.requestsSnapshot()
        let tokenRequest = try #require(tokenRequests.first?.buildURLRequest())
        let tokenTraceParent = try #require(tokenRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue))
        assertRequest(
            tokenRequest,
            path: "verifications/email/start",
            accessToken: "context-access-token",
            traceParent: tokenTraceParent
        ) { body in
            #expect(body.keys.isEmpty)
        }
    }

    @Test func `Email verification dropping controller does not request cancel`() async throws {
        let network = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "verifications/email/start", body: startBody(challengeID: "drop-challenge")))
            ]
        )
        var controller: (any EmailVerificationAPIController)? = try #require(
            await makeAPI(network: network, context: nil).start(
                params: EmailVerificationAPIParams(loginID: LoginID(id: "drop@example.test", type: .email))
            ).getOrNil()
        )
        #expect(controller?.challenge.challengeID == ChallengeID("drop-challenge"))

        controller = nil
        await Task.yield()

        let paths = await network.endpointPaths(suffixComponentCount: 3)
        #expect(paths == ["verifications/email/start"])
    }

    @Test func `Email verification task cancellation does not request server cancel`() async throws {
        let startNetwork = APIRecordingNetwork(suspendingAfter: [])
        let startTask = Task {
            await makeAPI(network: startNetwork, context: nil).start(
                params: EmailVerificationAPIParams(loginID: LoginID(id: "cancel-start@example.test", type: .email))
            )
        }
        await confirmation("email start request was sent before task cancellation") { requestSent in
            await startNetwork.waitForRequestCount(1)
            requestSent()
            startTask.cancel()
        }
        #expect(await startTask.value.isCanceled)
        #expect(await startNetwork.endpointPaths(suffixComponentCount: 3) == ["verifications/email/start"])

        let completeNetwork = APIRecordingNetwork(suspendingAfter: [])
        let controller = makeController(network: completeNetwork, challengeID: "cancel-complete-challenge")
        let completeTask = Task {
            await controller.completeWithCode(code: "123456")
        }
        await confirmation("email complete request was sent before task cancellation") { requestSent in
            await completeNetwork.waitForRequestCount(1)
            requestSent()
            completeTask.cancel()
        }
        #expect(await completeTask.value.isCanceled)
        #expect(await completeNetwork.endpointPaths(suffixComponentCount: 3) == ["verifications/email/complete"])

        let resendNetwork = APIRecordingNetwork(suspendingAfter: [])
        let resendController = makeController(network: resendNetwork, challengeID: "cancel-resend-challenge")
        let resendTask = Task {
            await resendController.resend()
        }
        await confirmation("email resend request was sent before task cancellation") { requestSent in
            await resendNetwork.waitForRequestCount(1)
            requestSent()
            resendTask.cancel()
        }
        #expect(await resendTask.value.isCanceled)
        #expect(await resendNetwork.endpointPaths(suffixComponentCount: 3) == ["verifications/email/resend"])
    }

    @Test func `Email verification requests build endpoint bodies and headers`() throws {
        let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"

        let startCall = try EmailVerificationStartAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "user@example.com", type: .email),
            loginIDHintID: "email-hint-id",
            accessToken: AccessToken(token: "start-access-token"),
            verificationMethods: [.magicLink, .otp],
            magicLinkRedirectURL: "ownid://verification/callback",
            traceParent: traceParent
        )
        assertRequest(
            startCall.request.buildURLRequest(),
            path: "verifications/email/start",
            accessToken: "start-access-token",
            traceParent: traceParent
        ) { body in
            assertLoginID(body["loginId"], id: "user@example.com", type: "Email")
            #expect(body["loginIdHintId"] as? String == "email-hint-id")
            #expect(body["magicLinkRedirectUrl"] as? String == "ownid://verification/callback")
            #expect(Set(body["verificationMethods"] as? [String] ?? []) == ["MagicLink", "Otp"])
            #expect(body.keys.sorted() == ["loginId", "loginIdHintId", "magicLinkRedirectUrl", "verificationMethods"])
        }

        let challengeID = ChallengeID("challenge-123")
        let completeCall = try EmailVerificationCompleteAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: challengeID,
            code: "123456",
            accessToken: AccessToken(token: "linked-access-token"),
            traceParent: traceParent
        )
        assertRequest(
            completeCall.request.buildURLRequest(),
            path: "verifications/email/complete",
            accessToken: "linked-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "challenge-123")
            #expect(body["code"] as? String == "123456")
            #expect(body.keys.sorted() == ["challengeId", "code"])
        }

        let resendCall = try EmailVerificationResendAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: challengeID,
            accessToken: nil,
            traceParent: nil
        )
        assertRequest(
            resendCall.request.buildURLRequest(),
            path: "verifications/email/resend",
            accessToken: nil,
            traceParent: nil
        ) { body in
            #expect(body["challengeId"] as? String == "challenge-123")
            #expect(body.keys.sorted() == ["challengeId"])
        }

        let cancelCall = try EmailVerificationCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: challengeID,
            accessToken: AccessToken(token: "cancel-access-token"),
            reason: .userClose(details: "ignored by API DTO"),
            traceParent: nil
        )
        assertRequest(
            cancelCall.request.buildURLRequest(),
            path: "verifications/email/cancel",
            accessToken: "cancel-access-token",
            traceParent: nil
        ) { body in
            #expect(body["challengeId"] as? String == "challenge-123")
            #expect(body["reason"] as? String == "userClose")
            #expect(body.keys.sorted() == ["challengeId", "reason"])
        }
    }

    @Test func `Email verification calls map success responses`() throws {
        assertStartChallenge(
            try makeStartCall().mapHttpSuccess(
                success(
                    code: 201,
                    path: "verifications/email/start",
                    body: """
                        {
                          "challengeId": "challenge-123",
                          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 0},
                          "timeout": 30000,
                          "attempts": 5,
                          "channel": {"channel": "u***@example.test", "id": "email-channel-id"},
                          "methods": {"otp": {"length": 6}, "magicLink": {}}
                        }
                        """
                )
            )
        )

        assertCompleteAccessToken(
            try makeCompleteCall().mapHttpSuccess(
                success(code: 200, path: "verifications/email/complete", body: #"{"accessToken":"access-token"}"#)
            )
        )
        assertCompleteProofToken(
            try makeCompleteCall().mapHttpSuccess(
                success(code: 200, path: "verifications/email/complete", body: #"{"proofToken":"proof-token"}"#)
            )
        )

        assertResendSuccess(
            try makeResendCall().mapHttpSuccess(success(code: 204, path: "verifications/email/resend", body: ""))
        )
        assertCancelSuccess(
            try makeCancelCall().mapHttpSuccess(success(code: 204, path: "verifications/email/cancel", body: ""))
        )
    }

    @Test func `Email verification start clamps low OTP length`() throws {
        let result = try makeStartCall().mapHttpSuccess(
            success(
                code: 201,
                path: "verifications/email/start",
                body: """
                    {
                      "challengeId": "challenge-123",
                      "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
                      "timeout": 30000,
                      "attempts": 5,
                      "channel": {"channel": "u***@example.test", "id": "email-channel-id"},
                      "methods": {"otp": {"length": 2}}
                    }
                    """
            )
        )

        guard case .success(let challenge) = result else {
            Issue.record("Expected start success, got \(result)")
            return
        }
        #expect(challenge.methods.otp?.length == 4)
    }

    @Test func `Email verification maps invalid start challenge body to unexpected`() throws {
        assertStartUnexpected(
            try makeStartCall().mapHttpSuccess(
                success(
                    code: 201,
                    path: "verifications/email/start",
                    body: """
                        {
                          "challengeId": "challenge-123",
                          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
                          "timeout": 30000,
                          "attempts": 5,
                          "methods": {"otp": {"length": 6}}
                        }
                        """
                )
            )
        )
        assertStartUnexpected(
            try makeStartCall().mapHttpSuccess(
                success(
                    code: 201,
                    path: "verifications/email/start",
                    body: """
                        {
                          "challengeId": "challenge-123",
                          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
                          "timeout": 30000,
                          "attempts": 5,
                          "channel": {"channel": "u***@example.test", "id": "email-channel-id"},
                          "methods": {}
                        }
                        """
                )
            )
        )
    }

    @Test func `Email verification calls map unexpected success statuses`() throws {
        assertStartUnexpected(
            try makeStartCall().mapHttpSuccess(success(code: 200, path: "verifications/email/start", body: "{}"))
        )
        assertCompleteUnexpected(
            try makeCompleteCall().mapHttpSuccess(success(code: 204, path: "verifications/email/complete", body: ""))
        )
        assertResendUnexpected(
            try makeResendCall().mapHttpSuccess(success(code: 200, path: "verifications/email/resend", body: ""))
        )
        assertCancelUnexpected(
            try makeCancelCall().mapHttpSuccess(success(code: 200, path: "verifications/email/cancel", body: ""))
        )
    }

    @Test func `Email verification calls map HTTP error failures`() throws {
        assertStartMissingChannel(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "verifications/email/start",
                    body: """
                        {
                          "errorCode": "missing_channel",
                          "message": "Email channel is unavailable",
                          "loginId": {"id": "user@example.com", "type": "Email"}
                        }
                        """
                )
            )
        )
        assertStartForbidden(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 403,
                    path: "verifications/email/start",
                    body: #"{"errorCode":"forbidden","message":"Email verification is forbidden"}"#
                )
            )
        )
        assertStartUserNotFound(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 404,
                    path: "verifications/email/start",
                    body: #"{"errorCode":"user_not_found","message":"Email verification user not found"}"#
                )
            )
        )
        assertStartProviderFailed(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 424,
                    path: "verifications/email/start",
                    body: """
                        {
                          "errorCode": "integration_error",
                          "message": "Email provider failed",
                          "scope": "channel"
                        }
                        """
                )
            )
        )
        assertStartMaximumChallenges(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 429,
                    path: "verifications/email/start",
                    body: #"{"errorCode":"maximum_challenges_reached","message":"Too many email challenges"}"#
                )
            )
        )

        assertCompleteWrongCode(
            try makeCompleteCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "verifications/email/complete",
                    body: """
                        {
                          "errorCode": "verification_code_wrong",
                          "message": "Wrong verification code",
                          "challengeId": "challenge-123"
                        }
                        """
                )
            )
        )

        assertResendMaximumAttempts(
            try makeResendCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "verifications/email/resend",
                    body: """
                        {
                          "errorCode": "maximum_resend_attempts_reached",
                          "message": "Resend limit reached",
                          "challengeId": "challenge-123"
                        }
                        """
                )
            )
        )
        assertResendProviderFailed(
            try makeResendCall().mapHttpError(
                httpError(
                    statusCode: 424,
                    path: "verifications/email/resend",
                    body: """
                        {
                          "errorCode": "integration_error",
                          "message": "Email resend provider failed",
                          "scope": "channel"
                        }
                        """
                )
            )
        )

        assertCancelMaximumAttempts(
            try makeCancelCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "verifications/email/cancel",
                    body: """
                        {
                          "errorCode": "maximum_attempts_reached",
                          "message": "Attempts exhausted",
                          "challengeId": "challenge-123"
                        }
                        """
                )
            )
        )
    }

    private func makeStartCall() throws -> EmailVerificationStartAPICall {
        try EmailVerificationStartAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "user@example.com", type: .email),
            loginIDHintID: nil,
            accessToken: nil,
            verificationMethods: nil,
            magicLinkRedirectURL: nil,
            traceParent: nil
        )
    }

    private func makeCompleteCall() throws -> EmailVerificationCompleteAPICall {
        try EmailVerificationCompleteAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("challenge-123"),
            code: "123456",
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeResendCall() throws -> EmailVerificationResendAPICall {
        try EmailVerificationResendAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("challenge-123"),
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeCancelCall() throws -> EmailVerificationCancelAPICall {
        try EmailVerificationCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("challenge-123"),
            accessToken: nil,
            reason: .timeout,
            traceParent: nil
        )
    }

    private func makeAPI(network: any NetworkProtocol, context: Context?) -> EmailVerificationAPIImpl {
        EmailVerificationAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: context,
            loginIDValidator: nil,
            interceptor: nil
        )
    }

    private func makeController(network: any NetworkProtocol, challengeID: String) -> EmailVerificationAPIControllerImpl {
        EmailVerificationAPIControllerImpl(
            apiBaseURL: baseURL,
            network: network,
            coder: coder,
            challenge: VerificationChallenge(
                challengeID: ChallengeID(challengeID),
                resendPolicy: .init(allow: true, attempts: 3, debounce: 1),
                timeout: Timeout(milliseconds: 30000),
                attempts: 5,
                methods: .init(otp: .init(length: 6), magicLink: nil),
                channel: OperationChannel(channel: "u***@example.test", id: "email-channel-id")
            ),
            accessToken: AccessToken(token: "controller-access-token"),
            traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00",
            interceptor: nil
        )
    }

    private func context(authz: Authz) -> Context {
        var builder = Context.Builder()
        builder.authz = authz
        return builder.build(scopeName: "email-test")
    }

    private func startBody(challengeID: String) -> String {
        """
        {
          "challengeId": "\(challengeID)",
          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
          "timeout": 30000,
          "attempts": 5,
          "channel": {"channel": "u***@example.test", "id": "email-channel-id"},
          "methods": {"otp": {"length": 6}}
        }
        """
    }

    private func success(code: Int, path: String, body: String) -> NetworkResponse.Success {
        NetworkResponse.Success(url: baseURL.appendingPathComponent(path), code: code, headers: [:], body: body)
    }

    private func httpError(statusCode: Int, path: String, body: String) -> NetworkResponse.Fail.HttpError {
        NetworkResponse.Fail.HttpError(url: baseURL.appendingPathComponent(path), statusCode: statusCode, headers: [:], body: body)
    }

    private func assertRequest(
        _ request: URLRequest,
        path: String,
        accessToken: String?,
        traceParent: String?,
        bodyAssertions: ([String: Any]) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent(path))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            bodyAssertions(try bodyObject(from: request))
        } catch {
            Issue.record("Failed to decode request body: \(error)")
        }
    }

    private func assertLoginID(_ value: Any?, id: String, type: String, file: StaticString = #filePath, line: UInt = #line) {
        let loginID = value as? [String: Any]
        #expect(loginID?["id"] as? String == id)
        #expect(loginID?["type"] as? String == type)
    }

    private func assertStartChallenge(
        _ result: APIResult<VerificationChallenge, EmailVerificationStartAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(let challenge) = result else {
            Issue.record("Expected start success, got \(result)")
            return
        }
        #expect(challenge.challengeID == ChallengeID("challenge-123"))
        #expect(challenge.resendPolicy.allow == true)
        #expect(challenge.resendPolicy.attempts == 3)
        #expect(challenge.resendPolicy.debounce == 1)
        #expect(challenge.timeout == Timeout(milliseconds: 30000))
        #expect(challenge.attempts == 5)
        #expect(challenge.methods.otp?.length == 6)
        #expect(challenge.methods.magicLink != nil)
        #expect(challenge.channel == OperationChannel(channel: "u***@example.test", id: "email-channel-id"))
    }

    private func assertCompleteAccessToken(
        _ result: APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.accessToken(let token)) = result else {
            Issue.record("Expected complete access token success, got \(result)")
            return
        }
        #expect(token == AccessToken(token: "access-token"))
    }

    private func assertCompleteProofToken(
        _ result: APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.proofToken(let token)) = result else {
            Issue.record("Expected complete proof token success, got \(result)")
            return
        }
        #expect(token == ProofToken(token: "proof-token"))
    }

    private func assertResendSuccess(
        _ result: APIResult<Void, EmailVerificationResendAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            Issue.record("Expected resend success, got \(result)")
            return
        }
    }

    private func assertCancelSuccess(
        _ result: APIResult<Void, EmailVerificationCancelAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            Issue.record("Expected cancel success, got \(result)")
            return
        }
    }

    private func assertStartUnexpected(
        _ result: APIResult<VerificationChallenge, EmailVerificationStartAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected start unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertCompleteUnexpected(
        _ result: APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected complete unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertResendUnexpected(
        _ result: APIResult<Void, EmailVerificationResendAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected resend unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertCancelUnexpected(
        _ result: APIResult<Void, EmailVerificationCancelAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected cancel unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertStartMissingChannel(
        _ failure: EmailVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.missingChannel(let errorCode, let message, let loginID)) = failure else {
            Issue.record("Expected start missing channel failure, got \(failure)")
            return
        }
        #expect(errorCode == .missingChannel)
        #expect(message == "Email channel is unavailable")
        #expect(loginID == LoginID(id: "user@example.com", type: .email))
    }

    private func assertStartForbidden(
        _ failure: EmailVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected start forbidden failure, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "Email verification is forbidden")
    }

    private func assertStartUserNotFound(
        _ failure: EmailVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .userNotFound(let errorCode, let message) = failure else {
            Issue.record("Expected start user not found failure, got \(failure)")
            return
        }
        #expect(errorCode == .userNotFound)
        #expect(message == "Email verification user not found")
    }

    private func assertStartProviderFailed(
        _ failure: EmailVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected start provider failed failure, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Email provider failed")
        #expect(scope == .channel)
    }

    private func assertStartMaximumChallenges(
        _ failure: EmailVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .maximumChallengesReached(let errorCode, let message) = failure else {
            Issue.record("Expected start maximum challenges failure, got \(failure)")
            return
        }
        #expect(errorCode == .maximumChallengesReached)
        #expect(message == "Too many email challenges")
    }

    private func assertCompleteWrongCode(
        _ failure: EmailVerificationCompleteAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.wrongCode(let errorCode, let message, let challengeID)) = failure else {
            Issue.record("Expected complete wrong code failure, got \(failure)")
            return
        }
        #expect(errorCode == .verificationCodeWrong)
        #expect(message == "Wrong verification code")
        #expect(challengeID == ChallengeID("challenge-123"))
    }

    private func assertResendMaximumAttempts(
        _ failure: EmailVerificationResendAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.maximumResendAttemptsReached(let errorCode, let message, let challengeID)) = failure else {
            Issue.record("Expected resend maximum attempts failure, got \(failure)")
            return
        }
        #expect(errorCode == .maximumResendAttemptsReached)
        #expect(message == "Resend limit reached")
        #expect(challengeID == ChallengeID("challenge-123"))
    }

    private func assertResendProviderFailed(
        _ failure: EmailVerificationResendAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected resend provider failed failure, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Email resend provider failed")
        #expect(scope == .channel)
    }

    private func assertCancelMaximumAttempts(
        _ failure: EmailVerificationCancelAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.maximumAttemptsReached(let errorCode, let message, let challengeID)) = failure else {
            Issue.record("Expected cancel maximum attempts failure, got \(failure)")
            return
        }
        #expect(errorCode == .maximumAttemptsReached)
        #expect(message == "Attempts exhausted")
        #expect(challengeID == ChallengeID("challenge-123"))
    }
}
