import Foundation
import Testing

@testable import OwnIDCore

struct PhoneVerificationAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Phone verification start returns controller that reuses captured challenge token and trace`() async throws {
        let traceParent = "00-11111111111111111111111111111111-2222222222222222-01"
        let network = APIRecordingNetwork(
            responses: [
                .success(
                    success(
                        code: 201,
                        path: "verifications/phone/start",
                        body: """
                            {
                              "challengeId": "controller-challenge",
                              "resendPolicy": {"allow": true, "attempts": 4, "debounce": 2},
                              "timeout": 45000,
                              "attempts": 6,
                              "channel": {"channel": "+1******4567", "id": "phone-channel-id"},
                              "methods": {"otp": {"length": 6}, "magicLink": {}}
                            }
                            """
                    )
                ),
                .success(success(code: 200, path: "verifications/phone/complete", body: #"{"accessToken":"verified-access-token"}"#)),
                .success(success(code: 204, path: "verifications/phone/resend", body: "")),
                .success(success(code: 204, path: "verifications/phone/cancel", body: "")),
            ]
        )
        let api = makeAPI(network: network, context: nil)

        let controller = try #require(
            await api.start(
                params: PhoneVerificationAPIParams(
                    loginID: LoginID(id: "+15551234567", type: .phoneNumber),
                    loginIDHintID: "params-hint",
                    accessToken: AccessToken(token: "captured-access-token"),
                    verificationMethods: [.otp],
                    magicLinkRedirectURL: nil,
                    traceParent: traceParent
                )
            ).getOrNil()
        )

        #expect(controller.challenge.challengeID == ChallengeID("controller-challenge"))
        #expect(controller.challenge.channel == OperationChannel(channel: "+1******4567", id: "phone-channel-id"))
        #expect((await controller.completeWithCode(code: "654321")).getOrNil() == .accessToken(AccessToken(token: "verified-access-token")))
        #expect((await controller.resend()).getOrNil() != nil)
        #expect((await controller.cancel(reason: .moveToOtherChallenge)).getOrNil() != nil)

        let requests = await network.requestsSnapshot()
        #expect(requests.count == 4)
        assertRequest(
            requests[0].buildURLRequest(),
            path: "verifications/phone/start",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            assertLoginID(body["loginId"], id: "+15551234567", type: "PhoneNumber")
            #expect(body["loginIdHintId"] as? String == "params-hint")
            #expect(body["verificationMethods"] as? [String] == ["Otp"])
            #expect(body.keys.sorted() == ["loginId", "loginIdHintId", "verificationMethods"])
        }
        assertRequest(
            requests[1].buildURLRequest(),
            path: "verifications/phone/complete",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "controller-challenge")
            #expect(body["code"] as? String == "654321")
            #expect(body.keys.sorted() == ["challengeId", "code"])
        }
        assertRequest(
            requests[2].buildURLRequest(),
            path: "verifications/phone/resend",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "controller-challenge")
            #expect(body.keys.sorted() == ["challengeId"])
        }
        assertRequest(
            requests[3].buildURLRequest(),
            path: "verifications/phone/cancel",
            accessToken: "captured-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "controller-challenge")
            #expect(body["reason"] as? String == "moveToOtherChallenge")
            #expect(body.keys.sorted() == ["challengeId", "reason"])
        }
    }

    @Test func `Phone verification start uses context login ID and access token fallbacks`() async throws {
        let loginIDContext = context(authz: .start(LoginID(id: "+15557654321", type: .phoneNumber)))
        let loginIDNetwork = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "verifications/phone/start", body: startBody(challengeID: "context-login-challenge")))
            ]
        )
        _ = await makeAPI(network: loginIDNetwork, context: loginIDContext).start(params: nil)
        let loginIDRequests = await loginIDNetwork.requestsSnapshot()
        let loginIDRequest = try #require(loginIDRequests.first?.buildURLRequest())
        let loginIDTraceParent = try #require(loginIDRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue))
        assertRequest(
            loginIDRequest,
            path: "verifications/phone/start",
            accessToken: nil,
            traceParent: loginIDTraceParent
        ) { body in
            assertLoginID(body["loginId"], id: "+15557654321", type: "PhoneNumber")
            #expect(body.keys.sorted() == ["loginId"])
        }

        let tokenContext = context(authz: .fromToken(AccessToken(token: "context-access-token")))
        let tokenNetwork = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "verifications/phone/start", body: startBody(challengeID: "context-token-challenge")))
            ]
        )
        _ = await makeAPI(network: tokenNetwork, context: tokenContext).start(params: nil)
        let tokenRequests = await tokenNetwork.requestsSnapshot()
        let tokenRequest = try #require(tokenRequests.first?.buildURLRequest())
        let tokenTraceParent = try #require(tokenRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue))
        assertRequest(
            tokenRequest,
            path: "verifications/phone/start",
            accessToken: "context-access-token",
            traceParent: tokenTraceParent
        ) { body in
            #expect(body.keys.isEmpty)
        }
    }

    @Test func `Phone verification dropping controller does not request cancel`() async throws {
        let network = APIRecordingNetwork(
            responses: [
                .success(success(code: 201, path: "verifications/phone/start", body: startBody(challengeID: "drop-challenge")))
            ]
        )
        var controller: (any PhoneVerificationAPIController)? = try #require(
            await makeAPI(network: network, context: nil).start(
                params: PhoneVerificationAPIParams(loginID: LoginID(id: "+15550001111", type: .phoneNumber))
            ).getOrNil()
        )
        #expect(controller?.challenge.challengeID == ChallengeID("drop-challenge"))

        controller = nil
        await Task.yield()

        let paths = await network.endpointPaths(suffixComponentCount: 3)
        #expect(paths == ["verifications/phone/start"])
    }

    @Test func `Phone verification task cancellation does not request server cancel`() async throws {
        let startNetwork = APIRecordingNetwork(suspendingAfter: [])
        let startTask = Task {
            await makeAPI(network: startNetwork, context: nil).start(
                params: PhoneVerificationAPIParams(loginID: LoginID(id: "+15559998888", type: .phoneNumber))
            )
        }
        await confirmation("phone start request was sent before task cancellation") { requestSent in
            await startNetwork.waitForRequestCount(1)
            requestSent()
            startTask.cancel()
        }
        #expect(await startTask.value.isCanceled)
        #expect(await startNetwork.endpointPaths(suffixComponentCount: 3) == ["verifications/phone/start"])

        let completeNetwork = APIRecordingNetwork(suspendingAfter: [])
        let controller = makeController(network: completeNetwork, challengeID: "cancel-complete-challenge")
        let completeTask = Task {
            await controller.completeWithCode(code: "123456")
        }
        await confirmation("phone complete request was sent before task cancellation") { requestSent in
            await completeNetwork.waitForRequestCount(1)
            requestSent()
            completeTask.cancel()
        }
        #expect(await completeTask.value.isCanceled)
        #expect(await completeNetwork.endpointPaths(suffixComponentCount: 3) == ["verifications/phone/complete"])

        let resendNetwork = APIRecordingNetwork(suspendingAfter: [])
        let resendController = makeController(network: resendNetwork, challengeID: "cancel-resend-challenge")
        let resendTask = Task {
            await resendController.resend()
        }
        await confirmation("phone resend request was sent before task cancellation") { requestSent in
            await resendNetwork.waitForRequestCount(1)
            requestSent()
            resendTask.cancel()
        }
        #expect(await resendTask.value.isCanceled)
        #expect(await resendNetwork.endpointPaths(suffixComponentCount: 3) == ["verifications/phone/resend"])
    }

    @Test func `Phone verification requests build endpoint bodies and headers`() throws {
        let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"

        let startCall = try PhoneVerificationStartAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "+15551234567", type: .phoneNumber),
            loginIDHintID: "phone-hint-id",
            accessToken: AccessToken(token: "start-access-token"),
            verificationMethods: [.magicLink, .otp],
            magicLinkRedirectURL: "ownid://verification/callback",
            traceParent: traceParent
        )
        assertRequest(
            startCall.request.buildURLRequest(),
            path: "verifications/phone/start",
            accessToken: "start-access-token",
            traceParent: traceParent
        ) { body in
            assertLoginID(body["loginId"], id: "+15551234567", type: "PhoneNumber")
            #expect(body["loginIdHintId"] as? String == "phone-hint-id")
            #expect(body["magicLinkRedirectUrl"] as? String == "ownid://verification/callback")
            #expect(Set(body["verificationMethods"] as? [String] ?? []) == ["MagicLink", "Otp"])
            #expect(body.keys.sorted() == ["loginId", "loginIdHintId", "magicLinkRedirectUrl", "verificationMethods"])
        }

        let challengeID = ChallengeID("challenge-123")
        let completeCall = try PhoneVerificationCompleteAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: challengeID,
            code: "123456",
            accessToken: AccessToken(token: "linked-access-token"),
            traceParent: traceParent
        )
        assertRequest(
            completeCall.request.buildURLRequest(),
            path: "verifications/phone/complete",
            accessToken: "linked-access-token",
            traceParent: traceParent
        ) { body in
            #expect(body["challengeId"] as? String == "challenge-123")
            #expect(body["code"] as? String == "123456")
            #expect(body.keys.sorted() == ["challengeId", "code"])
        }

        let resendCall = try PhoneVerificationResendAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: challengeID,
            accessToken: nil,
            traceParent: nil
        )
        assertRequest(
            resendCall.request.buildURLRequest(),
            path: "verifications/phone/resend",
            accessToken: nil,
            traceParent: nil
        ) { body in
            #expect(body["challengeId"] as? String == "challenge-123")
            #expect(body.keys.sorted() == ["challengeId"])
        }

        let cancelCall = try PhoneVerificationCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: challengeID,
            accessToken: AccessToken(token: "cancel-access-token"),
            reason: .userClose(details: "ignored by API DTO"),
            traceParent: nil
        )
        assertRequest(
            cancelCall.request.buildURLRequest(),
            path: "verifications/phone/cancel",
            accessToken: "cancel-access-token",
            traceParent: nil
        ) { body in
            #expect(body["challengeId"] as? String == "challenge-123")
            #expect(body["reason"] as? String == "userClose")
            #expect(body.keys.sorted() == ["challengeId", "reason"])
        }
    }

    @Test func `Phone verification calls map success responses`() throws {
        assertStartChallenge(
            try makeStartCall().mapHttpSuccess(
                success(
                    code: 201,
                    path: "verifications/phone/start",
                    body: """
                        {
                          "challengeId": "challenge-123",
                          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 0},
                          "timeout": 30000,
                          "attempts": 5,
                          "channel": {"channel": "+1******4567", "id": "phone-channel-id"},
                          "methods": {"otp": {"length": 6}, "magicLink": {}}
                        }
                        """
                )
            )
        )

        assertCompleteAccessToken(
            try makeCompleteCall().mapHttpSuccess(
                success(code: 200, path: "verifications/phone/complete", body: #"{"accessToken":"access-token"}"#)
            )
        )
        assertCompleteProofToken(
            try makeCompleteCall().mapHttpSuccess(
                success(code: 200, path: "verifications/phone/complete", body: #"{"proofToken":"proof-token"}"#)
            )
        )

        assertResendSuccess(
            try makeResendCall().mapHttpSuccess(success(code: 204, path: "verifications/phone/resend", body: ""))
        )
        assertCancelSuccess(
            try makeCancelCall().mapHttpSuccess(success(code: 204, path: "verifications/phone/cancel", body: ""))
        )
    }

    @Test func `Phone verification start clamps low OTP length`() throws {
        let result = try makeStartCall().mapHttpSuccess(
            success(
                code: 201,
                path: "verifications/phone/start",
                body: """
                    {
                      "challengeId": "challenge-123",
                      "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
                      "timeout": 30000,
                      "attempts": 5,
                      "channel": {"channel": "+1******4567", "id": "phone-channel-id"},
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

    @Test func `Phone verification maps invalid start challenge body to unexpected`() throws {
        assertStartUnexpected(
            try makeStartCall().mapHttpSuccess(
                success(
                    code: 201,
                    path: "verifications/phone/start",
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
                    path: "verifications/phone/start",
                    body: """
                        {
                          "challengeId": "challenge-123",
                          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
                          "timeout": 30000,
                          "attempts": 5,
                          "channel": {"channel": "+1******4567", "id": "phone-channel-id"},
                          "methods": {}
                        }
                        """
                )
            )
        )
    }

    @Test func `Phone verification calls map unexpected success statuses`() throws {
        assertStartUnexpected(
            try makeStartCall().mapHttpSuccess(success(code: 200, path: "verifications/phone/start", body: "{}"))
        )
        assertCompleteUnexpected(
            try makeCompleteCall().mapHttpSuccess(success(code: 204, path: "verifications/phone/complete", body: ""))
        )
        assertResendUnexpected(
            try makeResendCall().mapHttpSuccess(success(code: 200, path: "verifications/phone/resend", body: ""))
        )
        assertCancelUnexpected(
            try makeCancelCall().mapHttpSuccess(success(code: 200, path: "verifications/phone/cancel", body: ""))
        )
    }

    @Test func `Phone verification calls map HTTP error failures`() throws {
        assertStartMissingChannel(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "verifications/phone/start",
                    body: """
                        {
                          "errorCode": "missing_channel",
                          "message": "Phone channel is unavailable",
                          "loginId": {"id": "+15551234567", "type": "PhoneNumber"}
                        }
                        """
                )
            )
        )
        assertStartForbidden(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 403,
                    path: "verifications/phone/start",
                    body: #"{"errorCode":"forbidden","message":"Phone verification is forbidden"}"#
                )
            )
        )
        assertStartUserNotFound(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 404,
                    path: "verifications/phone/start",
                    body: #"{"errorCode":"user_not_found","message":"Phone verification user not found"}"#
                )
            )
        )
        assertStartProviderFailed(
            try makeStartCall().mapHttpError(
                httpError(
                    statusCode: 424,
                    path: "verifications/phone/start",
                    body: """
                        {
                          "errorCode": "integration_error",
                          "message": "Phone provider failed",
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
                    path: "verifications/phone/start",
                    body: #"{"errorCode":"maximum_challenges_reached","message":"Too many phone challenges"}"#
                )
            )
        )

        assertCompleteWrongCode(
            try makeCompleteCall().mapHttpError(
                httpError(
                    statusCode: 400,
                    path: "verifications/phone/complete",
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
                    path: "verifications/phone/resend",
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
                    path: "verifications/phone/resend",
                    body: """
                        {
                          "errorCode": "integration_error",
                          "message": "Phone resend provider failed",
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
                    path: "verifications/phone/cancel",
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

    private func makeStartCall() throws -> PhoneVerificationStartAPICall {
        try PhoneVerificationStartAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "+15551234567", type: .phoneNumber),
            loginIDHintID: nil,
            accessToken: nil,
            verificationMethods: nil,
            magicLinkRedirectURL: nil,
            traceParent: nil
        )
    }

    private func makeCompleteCall() throws -> PhoneVerificationCompleteAPICall {
        try PhoneVerificationCompleteAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("challenge-123"),
            code: "123456",
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeResendCall() throws -> PhoneVerificationResendAPICall {
        try PhoneVerificationResendAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("challenge-123"),
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeCancelCall() throws -> PhoneVerificationCancelAPICall {
        try PhoneVerificationCancelAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            challengeID: ChallengeID("challenge-123"),
            accessToken: nil,
            reason: .timeout,
            traceParent: nil
        )
    }

    private func makeAPI(network: any NetworkProtocol, context: Context?) -> PhoneVerificationAPIImpl {
        PhoneVerificationAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: context,
            loginIDValidator: nil,
            interceptor: nil
        )
    }

    private func makeController(network: any NetworkProtocol, challengeID: String) -> PhoneVerificationAPIControllerImpl {
        PhoneVerificationAPIControllerImpl(
            apiBaseURL: baseURL,
            network: network,
            coder: coder,
            challenge: VerificationChallenge(
                challengeID: ChallengeID(challengeID),
                resendPolicy: .init(allow: true, attempts: 3, debounce: 1),
                timeout: Timeout(milliseconds: 30000),
                attempts: 5,
                methods: .init(otp: .init(length: 6), magicLink: nil),
                channel: OperationChannel(channel: "+1******4567", id: "phone-channel-id")
            ),
            accessToken: AccessToken(token: "controller-access-token"),
            traceParent: "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-00",
            interceptor: nil
        )
    }

    private func context(authz: Authz) -> Context {
        var builder = Context.Builder()
        builder.authz = authz
        return builder.build(scopeName: "phone-test")
    }

    private func startBody(challengeID: String) -> String {
        """
        {
          "challengeId": "\(challengeID)",
          "resendPolicy": {"allow": true, "attempts": 3, "debounce": 1},
          "timeout": 30000,
          "attempts": 5,
          "channel": {"channel": "+1******4567", "id": "phone-channel-id"},
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
        _ result: APIResult<VerificationChallenge, PhoneVerificationStartAPIFailure>,
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
        #expect(challenge.channel == OperationChannel(channel: "+1******4567", id: "phone-channel-id"))
    }

    private func assertCompleteAccessToken(
        _ result: APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure>,
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
        _ result: APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure>,
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
        _ result: APIResult<Void, PhoneVerificationResendAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            Issue.record("Expected resend success, got \(result)")
            return
        }
    }

    private func assertCancelSuccess(
        _ result: APIResult<Void, PhoneVerificationCancelAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            Issue.record("Expected cancel success, got \(result)")
            return
        }
    }

    private func assertStartUnexpected(
        _ result: APIResult<VerificationChallenge, PhoneVerificationStartAPIFailure>,
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
        _ result: APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure>,
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
        _ result: APIResult<Void, PhoneVerificationResendAPIFailure>,
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
        _ result: APIResult<Void, PhoneVerificationCancelAPIFailure>,
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
        _ failure: PhoneVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.missingChannel(let errorCode, let message, let loginID)) = failure else {
            Issue.record("Expected start missing channel failure, got \(failure)")
            return
        }
        #expect(errorCode == .missingChannel)
        #expect(message == "Phone channel is unavailable")
        #expect(loginID == LoginID(id: "+15551234567", type: .phoneNumber))
    }

    private func assertStartForbidden(
        _ failure: PhoneVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected start forbidden failure, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == "Phone verification is forbidden")
    }

    private func assertStartUserNotFound(
        _ failure: PhoneVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .userNotFound(let errorCode, let message) = failure else {
            Issue.record("Expected start user not found failure, got \(failure)")
            return
        }
        #expect(errorCode == .userNotFound)
        #expect(message == "Phone verification user not found")
    }

    private func assertStartProviderFailed(
        _ failure: PhoneVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected start provider failed failure, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Phone provider failed")
        #expect(scope == .channel)
    }

    private func assertStartMaximumChallenges(
        _ failure: PhoneVerificationStartAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .maximumChallengesReached(let errorCode, let message) = failure else {
            Issue.record("Expected start maximum challenges failure, got \(failure)")
            return
        }
        #expect(errorCode == .maximumChallengesReached)
        #expect(message == "Too many phone challenges")
    }

    private func assertCompleteWrongCode(
        _ failure: PhoneVerificationCompleteAPIFailure,
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
        _ failure: PhoneVerificationResendAPIFailure,
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
        _ failure: PhoneVerificationResendAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected resend provider failed failure, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Phone resend provider failed")
        #expect(scope == .channel)
    }

    private func assertCancelMaximumAttempts(
        _ failure: PhoneVerificationCancelAPIFailure,
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
