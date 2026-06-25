import Foundation
import Testing

@testable import OwnIDCore

struct LoginDiscoverAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Discover and login requests build login endpoint body and headers`() throws {
        let discoverCall = try DiscoverAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "user@example.com", type: .email),
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        let discoverRequest = discoverCall.request.buildURLRequest()
        let discoverBody = try bodyObject(from: discoverRequest)

        #expect(discoverRequest.url == baseURL.appendingPathComponent("login"))
        #expect(discoverRequest.httpMethod == "POST")
        #expect(
            discoverRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        #expect(discoverRequest.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == nil)
        assertLoginID(discoverBody["loginId"], id: "user@example.com", type: "Email")
        assertPasskeyPeekEnabled(discoverBody["extendedClientCapabilities"])

        let loginCall = try LoginAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: nil,
            accessToken: AccessToken(token: "access-token"),
            traceParent: nil
        )
        let loginRequest = loginCall.request.buildURLRequest()
        let loginBody = try bodyObject(from: loginRequest)

        #expect(loginRequest.url == baseURL.appendingPathComponent("login"))
        #expect(loginRequest.httpMethod == "POST")
        #expect(loginRequest.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer access-token")
        #expect(loginRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == nil)
        #expect(loginBody["loginId"] == nil)
        assertPasskeyPeekEnabled(loginBody["extendedClientCapabilities"])
    }

    @Test func `Discover and login map created and auth required responses`() throws {
        let discoverCall = try makeDiscoverCall()
        let loginCall = try makeLoginCall()

        let createdBody = #"{"accessToken":"server-token","sessionPayload":{"session":"ok","count":1}}"#
        assertDiscoverLoginSuccess(discoverCall.mapHttpSuccess(success(code: 201, body: createdBody)))
        assertLoginSuccess(loginCall.mapHttpSuccess(success(code: 201, body: createdBody)))

        let authRequiredBody = """
            {
              "reason": "step-up",
              "authRequirements": {
                "targetScore": 10,
                "operations": [
                  {
                    "type": "EmailVerification",
                    "score": 5,
                    "channels": [{"channel": "u***@example.test", "id": "email-1"}]
                  }
                ]
              }
            }
            """
        assertDiscoverAuthRequired(discoverCall.mapHttpSuccess(success(code: 206, body: authRequiredBody)))
        assertLoginAuthRequired(loginCall.mapHttpSuccess(success(code: 206, body: authRequiredBody)))

        let accountBlockedBody = #"{"reason":"blocked by policy","accountBlocked":true}"#
        assertDiscoverAccountBlocked(discoverCall.mapHttpSuccess(success(code: 206, body: accountBlockedBody)))
        assertLoginAccountBlocked(loginCall.mapHttpSuccess(success(code: 206, body: accountBlockedBody)))

        let accountNotFoundBody = #"{"reason":"unknown account","accountNotFound":true}"#
        assertDiscoverAccountNotFound(discoverCall.mapHttpSuccess(success(code: 206, body: accountNotFoundBody)))
        assertLoginAccountNotFound(loginCall.mapHttpSuccess(success(code: 206, body: accountNotFoundBody)))

        let malformedNoSessionBody = #"{"reason":"missing no-session branch"}"#
        assertDiscoverUnexpected(discoverCall.mapHttpSuccess(success(code: 206, body: malformedNoSessionBody)))
        assertLoginUnexpected(loginCall.mapHttpSuccess(success(code: 206, body: malformedNoSessionBody)))
    }

    @Test func `Discover and login map bad-request HTTP failures`() throws {
        let body = """
            {
              "errorCode": "login_id_validation_failed",
              "message": "Login ID does not match",
              "loginId": { "id": "bad", "type": "Email" },
              "regex": "^[^@]+@example\\\\.test$"
            }
            """
        let failure = httpError(statusCode: 400, body: body)

        assertDiscoverInvalidLoginID(try makeDiscoverCall().mapHttpError(failure))
        assertLoginInvalidLoginID(try makeLoginCall().mapHttpError(failure))
    }

    @Test func `Discover and login map forbidden HTTP failures`() throws {
        let failure = httpError(
            statusCode: 403,
            body: #"{"errorCode":"forbidden","message":"Login is forbidden"}"#
        )

        assertDiscoverForbidden(try makeDiscoverCall().mapHttpError(failure))
        assertLoginForbidden(try makeLoginCall().mapHttpError(failure))
    }

    @Test func `Discover and login use blank forbidden fallback only for empty body`() throws {
        let blank = httpError(statusCode: 403, body: " \n ")
        let blankMessage = String(describing: NetworkResponse.Fail.httpError(blank))

        assertDiscoverForbidden(try makeDiscoverCall().mapHttpError(blank), message: blankMessage)
        assertLoginForbidden(try makeLoginCall().mapHttpError(blank), message: blankMessage)

        let malformed = httpError(statusCode: 403, body: "{}")
        assertDiscoverUnexpectedFailure(try makeDiscoverCall().mapHttpError(malformed))
        assertLoginUnexpectedFailure(try makeLoginCall().mapHttpError(malformed))
    }

    @Test func `Discover and login map failed dependency HTTP failures`() throws {
        let body = """
            {
              "errorCode": "integration_error",
              "message": "Provider failed",
              "scope": "session"
            }
            """
        let failure = httpError(statusCode: 424, body: body)

        assertDiscoverProviderFailed(try makeDiscoverCall().mapHttpError(failure))
        assertLoginProviderFailed(try makeLoginCall().mapHttpError(failure))

        let missingProviderBody = """
            {
              "errorCode": "missing_capability_provider",
              "message": "Session provider is not configured",
              "capability": "SessionProvider",
              "scope": "session"
            }
            """
        let missingProvider = httpError(statusCode: 424, body: missingProviderBody)

        assertDiscoverMissingProvider(try makeDiscoverCall().mapHttpError(missingProvider))
        assertLoginMissingProvider(try makeLoginCall().mapHttpError(missingProvider))
    }

    @Test func `Discover context login ID resolution failures map before network`() async {
        let missingValidatorAPI = makeDiscoverAPI(context: rawLoginIDContext(), validator: nil)
        assertDiscoverMissingLoginIDValidator(await missingValidatorAPI.start(params: nil))

        let unsupportedAPI = makeDiscoverAPI(
            context: rawLoginIDContext(),
            validator: LoginIDValidatorStub(result: .typeNotSupported(message: "Unsupported login ID type"))
        )
        assertDiscoverUnsupportedLoginIDType(await unsupportedAPI.start(params: nil))

        let invalidLoginID = LoginID(id: "bad", type: .email)
        let invalidAPI = makeDiscoverAPI(
            context: rawLoginIDContext(),
            validator: LoginIDValidatorStub(
                result: .validationFailed(
                    message: "Invalid login ID",
                    loginID: invalidLoginID,
                    regex: "^[^@]+@example\\.test$"
                )
            )
        )
        assertDiscoverInvalidContextLoginID(await invalidAPI.start(params: nil), loginID: invalidLoginID)
    }

    @Test func `Discover API uses params login ID before context and sends login request`() async throws {
        let network = APIRecordingNetwork(response: loginSuccess())
        let api = makeDiscoverAPI(
            context: loginIDContext(LoginID(id: "context@example.test", type: .email)),
            network: network,
            validator: LoginIDValidatorStub(result: .type(.email))
        )

        assertDiscoverLoginSuccess(
            await api.start(
                params: DiscoverAPIParams(
                    loginID: LoginID(id: "params@example.test", type: .email),
                    traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-1111111111111111-00"
                )
            )
        )

        let request = try #require(await network.onlyURLRequest())
        let body = try bodyObject(from: request)
        #expect(request.url == baseURL.appendingPathComponent("login"))
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-4bf92f3577b34da6a3ce929d0e0e4736-1111111111111111-00"
        )
        assertLoginID(body["loginId"], id: "params@example.test", type: "Email")
    }

    @Test func `Discover API falls back to context login ID`() async throws {
        let network = APIRecordingNetwork(response: loginSuccess())
        let api = makeDiscoverAPI(
            context: loginIDContext(LoginID(id: "context@example.test", type: .email)),
            network: network,
            validator: LoginIDValidatorStub(result: .type(.email))
        )

        assertDiscoverLoginSuccess(await api.start(params: nil))

        let request = try #require(await network.onlyURLRequest())
        let body = try bodyObject(from: request)
        #expect(request.url == baseURL.appendingPathComponent("login"))
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) != nil)
        assertLoginID(body["loginId"], id: "context@example.test", type: "Email")
    }

    @Test func `Discover API missing login ID fails before network`() async {
        let network = APIRecordingNetwork(response: loginSuccess())
        let api = makeDiscoverAPI(context: nil, network: network, validator: nil)

        assertDiscoverMissingLoginID(await api.start(params: nil))
        #expect(await network.requestCount() == 0)
    }

    @Test func `Login API uses params access token before context and sends login request`() async throws {
        let network = APIRecordingNetwork(response: loginSuccess())
        let api = makeLoginAPI(context: accessTokenContext("context-token"), network: network)

        assertLoginSuccess(
            await api.start(
                params: LoginAPIParams(
                    accessToken: AccessToken(token: "params-token"),
                    traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-2222222222222222-00"
                )
            )
        )

        let request = try #require(await network.onlyURLRequest())
        let body = try bodyObject(from: request)
        #expect(request.url == baseURL.appendingPathComponent("login"))
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer params-token")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-4bf92f3577b34da6a3ce929d0e0e4736-2222222222222222-00"
        )
        #expect(body["loginId"] == nil)
    }

    @Test func `Login API falls back to context access token`() async throws {
        let network = APIRecordingNetwork(response: loginSuccess())
        let api = makeLoginAPI(context: accessTokenContext("context-token"), network: network)

        assertLoginSuccess(await api.start(params: nil))

        let request = try #require(await network.onlyURLRequest())
        #expect(request.url == baseURL.appendingPathComponent("login"))
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.authorization.rawValue) == "Bearer context-token")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) != nil)
    }

    @Test func `Login API missing access token fails before network`() async {
        let network = APIRecordingNetwork(response: loginSuccess())
        let api = makeLoginAPI(context: nil, network: network)

        assertLoginMissingAccessToken(await api.start(params: nil))
        #expect(await network.requestCount() == 0)
    }

    @Test func `Discover and login caller cancellation returns canceled without cancel endpoint`() async throws {
        let discoverNetwork = APIRecordingNetwork(suspendingAfter: [])
        let discoverAPI = makeDiscoverAPI(
            context: loginIDContext(LoginID(id: "context@example.test", type: .email)),
            network: discoverNetwork,
            validator: LoginIDValidatorStub(result: .type(.email))
        )
        let discoverTask = Task {
            await discoverAPI.start(params: DiscoverAPIParams(loginID: LoginID(id: "params@example.test", type: .email)))
        }
        await discoverNetwork.waitForRequestCount(1)
        discoverTask.cancel()

        assertCanceled(await discoverTask.value)
        #expect((try await discoverNetwork.onlyURLRequest())?.url == baseURL.appendingPathComponent("login"))

        let loginNetwork = APIRecordingNetwork(suspendingAfter: [])
        let loginAPI = makeLoginAPI(context: accessTokenContext("context-token"), network: loginNetwork)
        let loginTask = Task {
            await loginAPI.start(params: LoginAPIParams(accessToken: AccessToken(token: "params-token")))
        }
        await loginNetwork.waitForRequestCount(1)
        loginTask.cancel()

        assertCanceled(await loginTask.value)
        #expect((try await loginNetwork.onlyURLRequest())?.url == baseURL.appendingPathComponent("login"))
    }

    private func makeDiscoverCall() throws -> DiscoverAPICall {
        try DiscoverAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: LoginID(id: "user@example.com", type: .email),
            traceParent: nil
        )
    }

    private func makeLoginCall() throws -> LoginAPICall {
        try LoginAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            loginID: nil,
            accessToken: AccessToken(token: "access-token"),
            traceParent: nil
        )
    }

    private func makeDiscoverAPI(
        context: Context?,
        network: any NetworkProtocol = APIUnusedNetwork(),
        validator: (any LoginIDValidator)?
    ) -> DiscoverAPIImpl {
        DiscoverAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: context,
            loginIDValidator: validator,
            interceptor: nil
        )
    }

    private func makeLoginAPI(context: Context?, network: any NetworkProtocol) -> LoginAPIImpl {
        LoginAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: coder,
            context: context,
            interceptor: nil
        )
    }

    private func rawLoginIDContext() -> Context {
        var builder = Context.Builder()
        builder.authz = .start("raw-login-id")
        return builder.build(scopeName: "LoginDiscoverAPIImplementationMappingTests")
    }

    private func loginIDContext(_ loginID: LoginID) -> Context {
        var builder = Context.Builder()
        builder.authz = .start(loginID)
        return builder.build(scopeName: "LoginDiscoverAPIImplementationMappingTests")
    }

    private func accessTokenContext(_ token: String) -> Context {
        var builder = Context.Builder()
        builder.authz = .fromToken(token)
        return builder.build(scopeName: "LoginDiscoverAPIImplementationMappingTests")
    }

    private func loginSuccess() -> NetworkResponse {
        .success(success(code: 201, body: #"{"accessToken":"server-token","sessionPayload":{"session":"ok","count":1}}"#))
    }

    private func success(code: Int, body: String) -> NetworkResponse.Success {
        NetworkResponse.Success(url: baseURL.appendingPathComponent("login"), code: code, headers: [:], body: body)
    }

    private func httpError(statusCode: Int, body: String) -> NetworkResponse.Fail.HttpError {
        NetworkResponse.Fail.HttpError(url: baseURL.appendingPathComponent("login"), statusCode: statusCode, headers: [:], body: body)
    }

    private func assertLoginID(_ value: Any?, id: String, type: String, file: StaticString = #filePath, line: UInt = #line) {
        let loginID = value as? [String: Any]
        #expect(loginID?["id"] as? String == id)
        #expect(loginID?["type"] as? String == type)
    }

    private func assertPasskeyPeekEnabled(_ value: Any?, file: StaticString = #filePath, line: UInt = #line) {
        let capabilities = value as? [String: Any]
        let passkeys = capabilities?["passkeys"] as? [String: Any]
        #expect(passkeys?["peek"] as? Bool == true)
    }

    private func assertDiscoverLoginSuccess(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.success(let success)) = result else {
            Issue.record("Expected discover login success, got \(result)")
            return
        }
        #expect(success.accessToken == AccessToken(token: "server-token"))
        #expect(success.sessionPayload == #"{"session":"ok","count":1}"#)
    }

    private func assertLoginSuccess(
        _ result: APIResult<LoginResponse, LoginAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.success(let success)) = result else {
            Issue.record("Expected login success, got \(result)")
            return
        }
        #expect(success.accessToken == AccessToken(token: "server-token"))
        #expect(success.sessionPayload == #"{"session":"ok","count":1}"#)
    }

    private func assertDiscoverAuthRequired(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.authRequired(let authRequired)) = result else {
            Issue.record("Expected discover auth required, got \(result)")
            return
        }
        assertAuthRequired(authRequired, file: file, line: line)
    }

    private func assertLoginAuthRequired(
        _ result: APIResult<LoginResponse, LoginAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.authRequired(let authRequired)) = result else {
            Issue.record("Expected login auth required, got \(result)")
            return
        }
        assertAuthRequired(authRequired, file: file, line: line)
    }

    private func assertDiscoverAccountBlocked(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.accountBlocked(let blocked)) = result else {
            Issue.record("Expected discover account blocked, got \(result)")
            return
        }
        #expect(blocked.reason == "blocked by policy")
    }

    private func assertLoginAccountBlocked(
        _ result: APIResult<LoginResponse, LoginAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.accountBlocked(let blocked)) = result else {
            Issue.record("Expected login account blocked, got \(result)")
            return
        }
        #expect(blocked.reason == "blocked by policy")
    }

    private func assertDiscoverAccountNotFound(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.accountNotFound(let notFound)) = result else {
            Issue.record("Expected discover account not found, got \(result)")
            return
        }
        #expect(notFound.reason == "unknown account")
    }

    private func assertLoginAccountNotFound(
        _ result: APIResult<LoginResponse, LoginAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success(.accountNotFound(let notFound)) = result else {
            Issue.record("Expected login account not found, got \(result)")
            return
        }
        #expect(notFound.reason == "unknown account")
    }

    private func assertDiscoverUnexpected(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected discover unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertDiscoverUnexpectedFailure(
        _ failure: DiscoverAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            Issue.record("Expected discover unexpected failure, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(underlyingError is APIUnexpectedError)
    }

    private func assertLoginUnexpected(
        _ result: APIResult<LoginResponse, LoginAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.unexpected(let errorCode, _, _)) = result else {
            Issue.record("Expected login unexpected failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
    }

    private func assertLoginUnexpectedFailure(
        _ failure: LoginAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            Issue.record("Expected login unexpected failure, got \(failure)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(underlyingError is APIUnexpectedError)
    }

    private func assertAuthRequired(_ authRequired: LoginResponse.AuthRequired, file: StaticString, line: UInt) {
        #expect(authRequired.reason == "step-up")
        #expect(authRequired.authRequirements.targetScore == 10)
        #expect(authRequired.authRequirements.operations.count == 1)
        #expect(authRequired.authRequirements.operations.first?.type == .emailVerification)
        #expect(authRequired.authRequirements.operations.first?.score == 5)
        #expect(authRequired.authRequirements.operations.first?.channels == [OperationChannel(channel: "u***@example.test", id: "email-1")])
    }

    private func assertDiscoverInvalidLoginID(
        _ failure: DiscoverAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidLoginID(let errorCode, let message, let loginID, let regex)) = failure else {
            Issue.record("Expected discover invalid login ID, got \(failure)")
            return
        }
        #expect(errorCode == .loginIDValidationFailed)
        #expect(message == "Login ID does not match")
        #expect(loginID == LoginID(id: "bad", type: .email))
        #expect(regex == #"^[^@]+@example\.test$"#)
    }

    private func assertLoginInvalidLoginID(
        _ failure: LoginAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badRequest(.invalidLoginID(let errorCode, let message, let loginID, let regex)) = failure else {
            Issue.record("Expected login invalid login ID, got \(failure)")
            return
        }
        #expect(errorCode == .loginIDValidationFailed)
        #expect(message == "Login ID does not match")
        #expect(loginID == LoginID(id: "bad", type: .email))
        #expect(regex == #"^[^@]+@example\.test$"#)
    }

    private func assertDiscoverForbidden(
        _ failure: DiscoverAPIFailure,
        message expectedMessage: String = "Login is forbidden",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected discover forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == expectedMessage)
    }

    private func assertLoginForbidden(
        _ failure: LoginAPIFailure,
        message expectedMessage: String = "Login is forbidden",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .forbidden(let errorCode, let message) = failure else {
            Issue.record("Expected login forbidden, got \(failure)")
            return
        }
        #expect(errorCode == .forbidden)
        #expect(message == expectedMessage)
    }

    private func assertDiscoverProviderFailed(
        _ failure: DiscoverAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected discover provider failed, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Provider failed")
        #expect(scope == .session)
    }

    private func assertLoginProviderFailed(
        _ failure: LoginAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.providerFailed(let errorCode, let message, let scope)) = failure else {
            Issue.record("Expected login provider failed, got \(failure)")
            return
        }
        #expect(errorCode == .integrationError)
        #expect(message == "Provider failed")
        #expect(scope == .session)
    }

    private func assertDiscoverMissingProvider(
        _ failure: DiscoverAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.missingProvider(let errorCode, let message, let capability, let scope)) = failure else {
            Issue.record("Expected discover missing provider, got \(failure)")
            return
        }
        #expect(errorCode == .missingCapabilityProvider)
        #expect(message == "Session provider is not configured")
        #expect(capability == "SessionProvider")
        #expect(scope == .session)
    }

    private func assertLoginMissingProvider(
        _ failure: LoginAPIFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failedDependency(.missingProvider(let errorCode, let message, let capability, let scope)) = failure else {
            Issue.record("Expected login missing provider, got \(failure)")
            return
        }
        #expect(errorCode == .missingCapabilityProvider)
        #expect(message == "Session provider is not configured")
        #expect(capability == "SessionProvider")
        #expect(scope == .session)
    }

    private func assertDiscoverMissingLoginIDValidator(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.failedDependency(.missingProvider(let errorCode, let message, let capability, let scope))) = result else {
            Issue.record("Expected missing LoginIDValidator failure, got \(result)")
            return
        }
        #expect(errorCode == .missingCapabilityProvider)
        #expect(!(message.isEmpty))
        #expect(capability == "LoginIdValidator")
        #expect(scope == .data)
    }

    private func assertDiscoverMissingLoginID(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.invalidArgument(let errorCode, let message))) = result else {
            Issue.record("Expected missing login ID failure, got \(result)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "LoginID is required")
    }

    private func assertLoginMissingAccessToken(
        _ result: APIResult<LoginResponse, LoginAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.invalidArgument(let errorCode, let message))) = result else {
            Issue.record("Expected missing access token failure, got \(result)")
            return
        }
        #expect(errorCode == .invalidArgument)
        #expect(message == "AccessToken is required")
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

    private func assertDiscoverUnsupportedLoginIDType(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.unsupportedLoginIDType(let errorCode, let message))) = result else {
            Issue.record("Expected unsupported login ID type failure, got \(result)")
            return
        }
        #expect(errorCode == .loginIDTypeNotSupported)
        #expect(message == "Unsupported login ID type")
    }

    private func assertDiscoverInvalidContextLoginID(
        _ result: APIResult<LoginResponse, DiscoverAPIFailure>,
        loginID: LoginID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.badRequest(.invalidLoginID(let errorCode, let message, let actualLoginID, let regex))) = result else {
            Issue.record("Expected invalid context login ID failure, got \(result)")
            return
        }
        #expect(errorCode == .loginIDValidationFailed)
        #expect(message == "Invalid login ID")
        #expect(actualLoginID == loginID)
        #expect(regex == #"^[^@]+@example\.test$"#)
    }
}

private struct LoginIDValidatorStub: LoginIDValidator {
    enum Result: Sendable {
        case type(LoginIDType)
        case typeNotSupported(message: String)
        case validationFailed(message: String, loginID: LoginID, regex: String)
    }

    let result: Result

    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        switch result {
        case .type(let type):
            return type
        case .typeNotSupported(let message):
            throw .typeNotSupported(errorCode: .loginIDTypeNotSupported, message: message)
        case .validationFailed(let message, let loginID, let regex):
            throw .validationFailed(errorCode: .loginIDValidationFailed, message: message, loginID: loginID, regex: regex)
        }
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        loginID
    }
}
