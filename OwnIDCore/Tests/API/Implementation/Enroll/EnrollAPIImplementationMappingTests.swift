import Foundation
import Testing

@testable import OwnIDCore

struct EnrollAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Enroll requests build endpoint bodies and headers`() throws {
        let emailCall = try EmailEnrollAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            proofToken: ProofToken(token: "email-proof-token"),
            accessToken: AccessToken(token: "email-access-token"),
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        assertEnrollRequest(
            emailCall.request.buildURLRequest(),
            path: "verifications/email/enroll",
            proofToken: "email-proof-token",
            accessToken: "email-access-token",
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )

        let phoneCall = try PhoneEnrollAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            proofToken: ProofToken(token: "phone-proof-token"),
            accessToken: nil,
            traceParent: nil
        )
        assertEnrollRequest(
            phoneCall.request.buildURLRequest(),
            path: "verifications/phone/enroll",
            proofToken: "phone-proof-token",
            accessToken: nil,
            traceParent: nil
        )

        let passkeyCall = try PasskeyEnrollAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            proofToken: ProofToken(token: "passkey-proof-token"),
            accessToken: AccessToken(token: "passkey-access-token"),
            traceParent: nil
        )
        assertEnrollRequest(
            passkeyCall.request.buildURLRequest(),
            path: "passkeys/attestation/enroll",
            proofToken: "passkey-proof-token",
            accessToken: "passkey-access-token",
            traceParent: nil
        )
    }

    @Test func `Enroll calls map no-content success only`() throws {
        assertEmailEnrollSuccess(try makeEmailCall().mapHttpSuccess(success(code: 204)))
        assertPhoneEnrollSuccess(try makePhoneCall().mapHttpSuccess(success(code: 204)))
        assertPasskeyEnrollSuccess(try makePasskeyCall().mapHttpSuccess(success(code: 204)))

        assertEmailEnrollUnexpected(try makeEmailCall().mapHttpSuccess(success(code: 200)))
        assertPhoneEnrollUnexpected(try makePhoneCall().mapHttpSuccess(success(code: 200)))
        assertPasskeyEnrollUnexpected(try makePasskeyCall().mapHttpSuccess(success(code: 200)))
    }

    @Test func `Enroll calls map bad-request invalid argument DTO failures`() throws {
        let failure = httpError(
            statusCode: 400,
            body: #"{"errorCode":"invalid_argument","message":"Proof token is invalid"}"#
        )

        assertEmailEnrollInvalidArgument(try makeEmailCall().mapHttpError(failure))
        assertPhoneEnrollInvalidArgument(try makePhoneCall().mapHttpError(failure))
        assertPasskeyEnrollInvalidArgument(try makePasskeyCall().mapHttpError(failure))

        let unknown = httpError(
            statusCode: 400,
            body: #"{"errorCode":"unknown","message":"Enroll request failed"}"#
        )

        assertEmailEnrollUnknown(try makeEmailCall().mapHttpError(unknown))
        assertPhoneEnrollUnknown(try makePhoneCall().mapHttpError(unknown))
        assertPasskeyEnrollUnknown(try makePasskeyCall().mapHttpError(unknown))
    }

    @Test func `Enroll calls map authorization user and dependency HTTP errors`() throws {
        let forbidden = httpError(
            statusCode: 403,
            body: #"{"errorCode":"forbidden","message":"Enrollment forbidden"}"#
        )
        assertEmailEnrollForbidden(try makeEmailCall().mapHttpError(forbidden))
        assertPhoneEnrollForbidden(try makePhoneCall().mapHttpError(forbidden))
        assertPasskeyEnrollForbidden(try makePasskeyCall().mapHttpError(forbidden))

        let userNotFound = httpError(
            statusCode: 404,
            body: #"{"errorCode":"user_not_found","message":"Enrollment user not found"}"#
        )
        assertEmailEnrollUserNotFound(try makeEmailCall().mapHttpError(userNotFound))
        assertPhoneEnrollUserNotFound(try makePhoneCall().mapHttpError(userNotFound))
        assertPasskeyEnrollUserNotFound(try makePasskeyCall().mapHttpError(userNotFound))

        let failedDependency = httpError(
            statusCode: 424,
            body: """
                {
                  "errorCode": "integration_error",
                  "message": "Enrollment provider failed",
                  "scope": "data"
                }
                """
        )
        assertEmailEnrollProviderFailed(try makeEmailCall().mapHttpError(failedDependency))
        assertPhoneEnrollProviderFailed(try makePhoneCall().mapHttpError(failedDependency))
        assertPasskeyEnrollProviderFailed(try makePasskeyCall().mapHttpError(failedDependency))

        let missingProvider = httpError(
            statusCode: 424,
            body: """
                {
                  "errorCode": "missing_capability_provider",
                  "message": "Enrollment provider is not configured",
                  "capability": "EnrollmentProvider",
                  "scope": "data"
                }
                """
        )
        assertEmailEnrollMissingProvider(try makeEmailCall().mapHttpError(missingProvider))
        assertPhoneEnrollMissingProvider(try makePhoneCall().mapHttpError(missingProvider))
        assertPasskeyEnrollMissingProvider(try makePasskeyCall().mapHttpError(missingProvider))
    }

    @Test func `Enroll calls use blank forbidden fallback only for empty body`() throws {
        let blank = httpError(statusCode: 403, body: " \n ")
        let blankMessage = String(describing: NetworkResponse.Fail.httpError(blank))

        assertEmailEnrollForbidden(try makeEmailCall().mapHttpError(blank), message: blankMessage)
        assertPhoneEnrollForbidden(try makePhoneCall().mapHttpError(blank), message: blankMessage)
        assertPasskeyEnrollForbidden(try makePasskeyCall().mapHttpError(blank), message: blankMessage)

        let malformed = httpError(statusCode: 403, body: "{}")
        assertEmailEnrollUnexpected(try makeEmailCall().mapHttpError(malformed))
        assertPhoneEnrollUnexpected(try makePhoneCall().mapHttpError(malformed))
        assertPasskeyEnrollUnexpected(try makePasskeyCall().mapHttpError(malformed))
    }

    @Test func `Enroll APIs use params proof and access token before context`() async throws {
        let emailNetwork = APIRecordingNetwork(response: enrollSuccess())
        let emailAPI = makeEmailAPI(context: accessTokenContext("context-token"), network: emailNetwork)
        assertEmailEnrollSuccess(
            await emailAPI.start(
                params: EmailEnrollAPIParams(
                    proofToken: ProofToken(token: "email-proof-token"),
                    accessToken: AccessToken(token: "email-params-token"),
                    traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-3333333333333333-00"
                )
            )
        )
        try assertCapturedEnrollRequest(
            await emailNetwork.onlyURLRequest(),
            path: "verifications/email/enroll",
            proofToken: "email-proof-token",
            accessToken: "email-params-token",
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-3333333333333333-00"
        )

        let phoneNetwork = APIRecordingNetwork(response: enrollSuccess())
        let phoneAPI = makePhoneAPI(context: accessTokenContext("context-token"), network: phoneNetwork)
        assertPhoneEnrollSuccess(
            await phoneAPI.start(
                params: PhoneEnrollAPIParams(
                    proofToken: ProofToken(token: "phone-proof-token"),
                    accessToken: AccessToken(token: "phone-params-token"),
                    traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-4444444444444444-00"
                )
            )
        )
        try assertCapturedEnrollRequest(
            await phoneNetwork.onlyURLRequest(),
            path: "verifications/phone/enroll",
            proofToken: "phone-proof-token",
            accessToken: "phone-params-token",
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-4444444444444444-00"
        )

        let passkeyNetwork = APIRecordingNetwork(response: enrollSuccess())
        let passkeyAPI = makePasskeyAPI(context: accessTokenContext("context-token"), network: passkeyNetwork)
        assertPasskeyEnrollSuccess(
            await passkeyAPI.start(
                params: PasskeyEnrollAPIParams(
                    proofToken: ProofToken(token: "passkey-proof-token"),
                    accessToken: AccessToken(token: "passkey-params-token"),
                    traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-5555555555555555-00"
                )
            )
        )
        try assertCapturedEnrollRequest(
            await passkeyNetwork.onlyURLRequest(),
            path: "passkeys/attestation/enroll",
            proofToken: "passkey-proof-token",
            accessToken: "passkey-params-token",
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-5555555555555555-00"
        )
    }

    @Test func `Enroll APIs fall back to context access token`() async throws {
        let emailNetwork = APIRecordingNetwork(response: enrollSuccess())
        let emailAPI = makeEmailAPI(context: accessTokenContext("context-token"), network: emailNetwork)
        assertEmailEnrollSuccess(
            await emailAPI.start(params: EmailEnrollAPIParams(proofToken: ProofToken(token: "email-proof-token")))
        )
        try assertCapturedEnrollRequest(
            await emailNetwork.onlyURLRequest(),
            path: "verifications/email/enroll",
            proofToken: "email-proof-token",
            accessToken: "context-token",
            traceParent: nil,
            requireGeneratedTraceParent: true
        )

        let phoneNetwork = APIRecordingNetwork(response: enrollSuccess())
        let phoneAPI = makePhoneAPI(context: accessTokenContext("context-token"), network: phoneNetwork)
        assertPhoneEnrollSuccess(
            await phoneAPI.start(params: PhoneEnrollAPIParams(proofToken: ProofToken(token: "phone-proof-token")))
        )
        try assertCapturedEnrollRequest(
            await phoneNetwork.onlyURLRequest(),
            path: "verifications/phone/enroll",
            proofToken: "phone-proof-token",
            accessToken: "context-token",
            traceParent: nil,
            requireGeneratedTraceParent: true
        )

        let passkeyNetwork = APIRecordingNetwork(response: enrollSuccess())
        let passkeyAPI = makePasskeyAPI(context: accessTokenContext("context-token"), network: passkeyNetwork)
        assertPasskeyEnrollSuccess(
            await passkeyAPI.start(params: PasskeyEnrollAPIParams(proofToken: ProofToken(token: "passkey-proof-token")))
        )
        try assertCapturedEnrollRequest(
            await passkeyNetwork.onlyURLRequest(),
            path: "passkeys/attestation/enroll",
            proofToken: "passkey-proof-token",
            accessToken: "context-token",
            traceParent: nil,
            requireGeneratedTraceParent: true
        )
    }

    @Test func `Enroll APIs missing access token fail before request execution`() async throws {
        let emailAPIBaseURL = RecordingAPIBaseURL(url: baseURL)
        let emailNetwork = APIRecordingNetwork(response: enrollSuccess())
        let emailInterceptor = RecordingAPICallInterceptor()
        let emailAPI = makeEmailAPI(
            apiBaseURL: emailAPIBaseURL,
            context: nil,
            network: emailNetwork,
            interceptor: emailInterceptor
        )
        assertEmailEnrollMissingAccessToken(
            await emailAPI.start(params: EmailEnrollAPIParams(proofToken: ProofToken(token: "email-proof-token")))
        )
        await assertNoRequestExecution(apiBaseURL: emailAPIBaseURL, network: emailNetwork, interceptor: emailInterceptor)

        let phoneAPIBaseURL = RecordingAPIBaseURL(url: baseURL)
        let phoneNetwork = APIRecordingNetwork(response: enrollSuccess())
        let phoneInterceptor = RecordingAPICallInterceptor()
        let phoneAPI = makePhoneAPI(
            apiBaseURL: phoneAPIBaseURL,
            context: nil,
            network: phoneNetwork,
            interceptor: phoneInterceptor
        )
        assertPhoneEnrollMissingAccessToken(
            await phoneAPI.start(params: PhoneEnrollAPIParams(proofToken: ProofToken(token: "phone-proof-token")))
        )
        await assertNoRequestExecution(apiBaseURL: phoneAPIBaseURL, network: phoneNetwork, interceptor: phoneInterceptor)

        let passkeyAPIBaseURL = RecordingAPIBaseURL(url: baseURL)
        let passkeyNetwork = APIRecordingNetwork(response: enrollSuccess())
        let passkeyInterceptor = RecordingAPICallInterceptor()
        let passkeyAPI = makePasskeyAPI(
            apiBaseURL: passkeyAPIBaseURL,
            context: nil,
            network: passkeyNetwork,
            interceptor: passkeyInterceptor
        )
        assertPasskeyEnrollMissingAccessToken(
            await passkeyAPI.start(params: PasskeyEnrollAPIParams(proofToken: ProofToken(token: "passkey-proof-token")))
        )
        await assertNoRequestExecution(
            apiBaseURL: passkeyAPIBaseURL,
            network: passkeyNetwork,
            interceptor: passkeyInterceptor
        )
    }

    @Test func `Enroll API caller cancellation returns canceled`() async throws {
        let emailNetwork = APIRecordingNetwork(suspendingAfter: [])
        let emailAPI = makeEmailAPI(context: accessTokenContext("context-token"), network: emailNetwork)
        let emailTask = Task {
            await emailAPI.start(params: EmailEnrollAPIParams(proofToken: ProofToken(token: "email-proof-token")))
        }
        await emailNetwork.waitForRequestCount(1)
        emailTask.cancel()
        assertCanceled(await emailTask.value)
        #expect((try await emailNetwork.onlyURLRequest())?.url == baseURL.appendingPathComponent("verifications/email/enroll"))

        let phoneNetwork = APIRecordingNetwork(suspendingAfter: [])
        let phoneAPI = makePhoneAPI(context: accessTokenContext("context-token"), network: phoneNetwork)
        let phoneTask = Task {
            await phoneAPI.start(params: PhoneEnrollAPIParams(proofToken: ProofToken(token: "phone-proof-token")))
        }
        await phoneNetwork.waitForRequestCount(1)
        phoneTask.cancel()
        assertCanceled(await phoneTask.value)
        #expect((try await phoneNetwork.onlyURLRequest())?.url == baseURL.appendingPathComponent("verifications/phone/enroll"))

        let passkeyNetwork = APIRecordingNetwork(suspendingAfter: [])
        let passkeyAPI = makePasskeyAPI(context: accessTokenContext("context-token"), network: passkeyNetwork)
        let passkeyTask = Task {
            await passkeyAPI.start(params: PasskeyEnrollAPIParams(proofToken: ProofToken(token: "passkey-proof-token")))
        }
        await passkeyNetwork.waitForRequestCount(1)
        passkeyTask.cancel()
        assertCanceled(await passkeyTask.value)
        #expect((try await passkeyNetwork.onlyURLRequest())?.url == baseURL.appendingPathComponent("passkeys/attestation/enroll"))
    }

    private func makeEmailCall() throws -> EmailEnrollAPICall {
        try EmailEnrollAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            proofToken: ProofToken(token: "email-proof-token"),
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makePhoneCall() throws -> PhoneEnrollAPICall {
        try PhoneEnrollAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            proofToken: ProofToken(token: "phone-proof-token"),
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makePasskeyCall() throws -> PasskeyEnrollAPICall {
        try PasskeyEnrollAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            proofToken: ProofToken(token: "passkey-proof-token"),
            accessToken: nil,
            traceParent: nil
        )
    }

    private func makeEmailAPI(context: Context?, network: any NetworkProtocol) -> EmailEnrollAPIImpl {
        makeEmailAPI(apiBaseURL: StaticAPIBaseURL(url: baseURL), context: context, network: network, interceptor: nil)
    }

    private func makeEmailAPI(
        apiBaseURL: any APIBaseURL,
        context: Context?,
        network: any NetworkProtocol,
        interceptor: (any APICallInterceptor)?
    ) -> EmailEnrollAPIImpl {
        EmailEnrollAPIImpl(
            apiBaseURL: apiBaseURL,
            network: network,
            coder: coder,
            context: context,
            interceptor: interceptor
        )
    }

    private func makePhoneAPI(context: Context?, network: any NetworkProtocol) -> PhoneEnrollAPIImpl {
        makePhoneAPI(apiBaseURL: StaticAPIBaseURL(url: baseURL), context: context, network: network, interceptor: nil)
    }

    private func makePhoneAPI(
        apiBaseURL: any APIBaseURL,
        context: Context?,
        network: any NetworkProtocol,
        interceptor: (any APICallInterceptor)?
    ) -> PhoneEnrollAPIImpl {
        PhoneEnrollAPIImpl(
            apiBaseURL: apiBaseURL,
            network: network,
            coder: coder,
            context: context,
            interceptor: interceptor
        )
    }

    private func makePasskeyAPI(context: Context?, network: any NetworkProtocol) -> PasskeyEnrollAPIImpl {
        makePasskeyAPI(apiBaseURL: StaticAPIBaseURL(url: baseURL), context: context, network: network, interceptor: nil)
    }

    private func makePasskeyAPI(
        apiBaseURL: any APIBaseURL,
        context: Context?,
        network: any NetworkProtocol,
        interceptor: (any APICallInterceptor)?
    ) -> PasskeyEnrollAPIImpl {
        PasskeyEnrollAPIImpl(
            apiBaseURL: apiBaseURL,
            network: network,
            coder: coder,
            context: context,
            interceptor: interceptor
        )
    }

    private func accessTokenContext(_ token: String) -> Context {
        var builder = Context.Builder()
        builder.authz = .fromToken(token)
        return builder.build(scopeName: "EnrollAPIImplementationMappingTests")
    }

    private func enrollSuccess() -> NetworkResponse {
        .success(success(code: 204))
    }

    private func success(code: Int) -> NetworkResponse.Success {
        NetworkResponse.Success(url: baseURL, code: code, headers: [:], body: "")
    }

    private func httpError(statusCode: Int, body: String) -> NetworkResponse.Fail.HttpError {
        NetworkResponse.Fail.HttpError(url: baseURL, statusCode: statusCode, headers: [:], body: body)
    }

    private func assertEnrollRequest(
        _ request: URLRequest,
        path: String,
        proofToken: String,
        accessToken: String?,
        traceParent: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(request.url == baseURL.appendingPathComponent(path))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == accessToken.map { "Bearer \($0)" })
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)

        do {
            let body = try bodyObject(from: request)
            #expect(body["proofToken"] as? String == proofToken)
            #expect(body.keys.sorted() == ["proofToken"])
        } catch {
            Issue.record("Failed to decode request body: \(error)")
        }
    }

    private func assertCapturedEnrollRequest(
        _ request: URLRequest?,
        path: String,
        proofToken: String,
        accessToken: String?,
        traceParent: String?,
        requireGeneratedTraceParent: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let request = try #require(request)
        assertEnrollRequest(
            request,
            path: path,
            proofToken: proofToken,
            accessToken: accessToken,
            traceParent: requireGeneratedTraceParent
                ? request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                : traceParent,
            file: file,
            line: line
        )
        if requireGeneratedTraceParent {
            #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) != nil)
        }
    }

    private func assertNoRequestExecution(
        apiBaseURL: RecordingAPIBaseURL,
        network: APIRecordingNetwork,
        interceptor: RecordingAPICallInterceptor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        #expect(apiBaseURL.callCount == 0, "API base URL lookup must not run before the missing-token failure.")
        #expect(await network.requestCount() == 0, "Network must not run before the missing-token failure.")
        #expect(
            await interceptor.interceptRequestCount() == 0,
            "Request interceptor must not run before the missing-token failure."
        )
        #expect(
            await interceptor.onResponseCount() == 0,
            "Response interceptor must not run before the missing-token failure."
        )
    }

    private func assertEmailEnrollSuccess(
        _ result: APIResult<Void, EmailEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            Issue.record("Expected email enroll success, got \(result)")
            return
        }
    }

    private func assertPhoneEnrollSuccess(
        _ result: APIResult<Void, PhoneEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            Issue.record("Expected phone enroll success, got \(result)")
            return
        }
    }

    private func assertPasskeyEnrollSuccess(
        _ result: APIResult<Void, PasskeyEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            Issue.record("Expected passkey enroll success, got \(result)")
            return
        }
    }

    private func assertEmailEnrollUnexpected(
        _ result: APIResult<Void, EmailEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected email enroll unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertEmailEnrollUnexpected(
        _ failure: EmailEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            Issue.record("Expected email enroll unexpected failure, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(underlyingError is APIUnexpectedError)
    }

    private func assertPhoneEnrollUnexpected(
        _ result: APIResult<Void, PhoneEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected phone enroll unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertPhoneEnrollUnexpected(
        _ failure: PhoneEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            Issue.record("Expected phone enroll unexpected failure, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(underlyingError is APIUnexpectedError)
    }

    private func assertPasskeyEnrollUnexpected(
        _ result: APIResult<Void, PasskeyEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected passkey enroll unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertPasskeyEnrollUnexpected(
        _ failure: PasskeyEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            Issue.record("Expected passkey enroll unexpected failure, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(underlyingError is APIUnexpectedError)
    }

    private func assertEmailEnrollInvalidArgument(
        _ failure: EmailEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidArgument(let errorCode, let message)) = failure else {
            Issue.record("Expected email enroll invalid argument, got \(failure)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "Proof token is invalid")
    }

    private func assertEmailEnrollMissingAccessToken(
        _ result: APIResult<Void, EmailEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.invalidArgument(let errorCode, let message))) = result else {
            Issue.record("Expected email enroll missing access token bad request, got \(result)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "AccessToken is required")
    }

    private func assertEmailEnrollUnknown(
        _ failure: EmailEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.unknown(let errorCode, let message)) = failure else {
            Issue.record("Expected email enroll unknown, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(message == "Enroll request failed")
    }

    private func assertPhoneEnrollUnknown(
        _ failure: PhoneEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.unknown(let errorCode, let message)) = failure else {
            Issue.record("Expected phone enroll unknown, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(message == "Enroll request failed")
    }

    private func assertPasskeyEnrollUnknown(
        _ failure: PasskeyEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.unknown(let errorCode, let message)) = failure else {
            Issue.record("Expected passkey enroll unknown, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(message == "Enroll request failed")
    }

    private func assertPhoneEnrollInvalidArgument(
        _ failure: PhoneEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidArgument(let errorCode, let message)) = failure else {
            Issue.record("Expected phone enroll invalid argument, got \(failure)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "Proof token is invalid")
    }

    private func assertPhoneEnrollMissingAccessToken(
        _ result: APIResult<Void, PhoneEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.invalidArgument(let errorCode, let message))) = result else {
            Issue.record("Expected phone enroll missing access token bad request, got \(result)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "AccessToken is required")
    }

    private func assertPasskeyEnrollInvalidArgument(
        _ failure: PasskeyEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidArgument(let errorCode, let message)) = failure else {
            Issue.record("Expected passkey enroll invalid argument, got \(failure)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "Proof token is invalid")
    }

    private func assertPasskeyEnrollMissingAccessToken(
        _ result: APIResult<Void, PasskeyEnrollAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.invalidArgument(let errorCode, let message))) = result else {
            Issue.record("Expected passkey enroll missing access token bad request, got \(result)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "AccessToken is required")
    }

    private func assertEmailEnrollForbidden(
        _ failure: EmailEnrollAPIFailure,
        message expectedMessage: String = "Enrollment forbidden",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected email enroll forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == expectedMessage)
    }

    private func assertPhoneEnrollForbidden(
        _ failure: PhoneEnrollAPIFailure,
        message expectedMessage: String = "Enrollment forbidden",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected phone enroll forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == expectedMessage)
    }

    private func assertPasskeyEnrollForbidden(
        _ failure: PasskeyEnrollAPIFailure,
        message expectedMessage: String = "Enrollment forbidden",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected passkey enroll forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == expectedMessage)
    }

    private func assertEmailEnrollUserNotFound(
        _ failure: EmailEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .userNotFound(let errorCode, let message) = failure else {
            Issue.record("Expected email enroll user not found, got \(failure)")
            return
        }
        #expect(errorCode == .userNotFound)
        #expect(message == "Enrollment user not found")
    }

    private func assertPhoneEnrollUserNotFound(
        _ failure: PhoneEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .userNotFound(let errorCode, let message) = failure else {
            Issue.record("Expected phone enroll user not found, got \(failure)")
            return
        }
        #expect(errorCode == .userNotFound)
        #expect(message == "Enrollment user not found")
    }

    private func assertPasskeyEnrollUserNotFound(
        _ failure: PasskeyEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .userNotFound(let errorCode, let message) = failure else {
            Issue.record("Expected passkey enroll user not found, got \(failure)")
            return
        }
        #expect(errorCode == .userNotFound)
        #expect(message == "Enrollment user not found")
    }

    private func assertEmailEnrollProviderFailed(
        _ failure: EmailEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected email enroll provider failed, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Enrollment provider failed")
        #expect(scope == .data)
    }

    private func assertPhoneEnrollProviderFailed(
        _ failure: PhoneEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected phone enroll provider failed, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Enrollment provider failed")
        #expect(scope == .data)
    }

    private func assertPasskeyEnrollProviderFailed(
        _ failure: PasskeyEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected passkey enroll provider failed, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Enrollment provider failed")
        #expect(scope == .data)
    }

    private func assertEmailEnrollMissingProvider(
        _ failure: EmailEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.missingProvider(let errorCode, let message, let capability, let scope)) = failure else {
            Issue.record("Expected email enroll missing provider, got \(failure)")
            return
        }
        #expect(errorCode == .missingCapabilityProvider)
        #expect(message == "Enrollment provider is not configured")
        #expect(capability == "EnrollmentProvider")
        #expect(scope == .data)
    }

    private func assertPhoneEnrollMissingProvider(
        _ failure: PhoneEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.missingProvider(let errorCode, let message, let capability, let scope)) = failure else {
            Issue.record("Expected phone enroll missing provider, got \(failure)")
            return
        }
        #expect(errorCode == .missingCapabilityProvider)
        #expect(message == "Enrollment provider is not configured")
        #expect(capability == "EnrollmentProvider")
        #expect(scope == .data)
    }

    private func assertPasskeyEnrollMissingProvider(
        _ failure: PasskeyEnrollAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.missingProvider(let errorCode, let message, let capability, let scope)) = failure else {
            Issue.record("Expected passkey enroll missing provider, got \(failure)")
            return
        }
        #expect(errorCode == .missingCapabilityProvider)
        #expect(message == "Enrollment provider is not configured")
        #expect(capability == "EnrollmentProvider")
        #expect(scope == .data)
    }

    private func assertCanceled<Success: Sendable, Failure: Sendable>(
        _ result: APIResult<Success, Failure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .canceled = result else {
            Issue.record("Expected canceled result, got \(result)")
            return
        }
    }
}

private final class RecordingAPIBaseURL: APIBaseURL, @unchecked Sendable {
    private let counter = LockedCounter()
    private let url: URL

    var callCount: Int { counter.value }

    init(url: URL) {
        self.url = url
    }

    func getBaseURL() throws -> URL {
        _ = counter.increment()
        return url
    }
}

private actor RecordingAPICallInterceptor: APICallInterceptor {
    private var requestCount = 0
    private var responseCount = 0

    func interceptRequest(_ request: NetworkRequest) async -> NetworkRequest {
        requestCount += 1
        return request
    }

    func onResponse<APISuccess: Sendable, APIFailure: Sendable>(
        request: NetworkRequest,
        response: APIResult<APISuccess, APIFailure>
    ) async -> APIResult<APISuccess, APIFailure> {
        responseCount += 1
        return response
    }

    func interceptRequestCount() -> Int {
        requestCount
    }

    func onResponseCount() -> Int {
        responseCount
    }
}
