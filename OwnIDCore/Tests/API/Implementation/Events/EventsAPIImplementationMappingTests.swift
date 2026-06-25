import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct EventsAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()
    private let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"

    @Test func `Request builds journey event endpoint and preserves analytics payload fields`() throws {
        let call = try EventsAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            userJourney: userJourneySummary(),
            traceParent: traceParent
        )

        let request = call.request.buildURLRequest()
        let body = try bodyObject(from: request)

        #expect(request.url == baseURL.appendingPathComponent("event/journey"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue) == traceParent)
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.accept.rawValue) == "application/json")
        #expect(request.value(forHTTPHeaderField: NetworkRequest.Header.cacheControl.rawValue) == "no-store")

        #expect(body["id"] as? String == "journey-1")
        #expect(body["traceparent"] as? String == traceParent)

        let reporter = try #require(body["reporter"] as? [String: Any])
        #expect(reporter["service"] as? String == "ios-sdk")
        #expect(reporter["origin"] as? String == "com.example.app")
        #expect(reporter["referer"] as? String == "ios-app://com.example.app/login")
        #expect(reporter["version"] as? String == "1.2.3")

        let deviceInfo = try #require(body["deviceInfo"] as? [String: Any])
        #expect(deviceInfo["isPlatformAuthenticatorAvailable"] as? Bool == true)
        #expect(deviceInfo["isWebView"] as? Bool == false)
        #expect(deviceInfo["isMobileNative"] as? Bool == true)

        let userInfo = try #require((body["userInfo"] as? [[String: Any]])?.first)
        let loginID = try #require(userInfo["loginId"] as? [String: Any])
        #expect(loginID["id"] as? String == "user@example.com")
        #expect(loginID["type"] as? String == "Email")
        #expect(userInfo["returningUser"] as? Bool == true)
        #expect(userInfo["lastAuthMethod"] as? String == "otp")

        let eventInfo = try #require(body["eventInfo"] as? [String: Any])
        #expect(eventInfo["type"] as? String == "journey-summary")

        let flow = try #require((eventInfo["flows"] as? [[String: Any]])?.first)
        #expect(flow["id"] as? String == "flow-1")
        #expect(flow["name"] as? String == "boost-login")
        #expect(flow["source"] as? String == "explicit")
        #expect(flow["status"] as? String == "completed")
        #expect(flow["startedAt"] as? String == "2024-01-01T00:00:00.123Z")
        #expect(flow["completedAt"] as? String == "2024-01-01T00:00:02.123Z")
        #expect(flow["switchedToFlow"] as? String == "flow-2")

        let flowError = try #require((flow["errors"] as? [[String: Any]])?.first)
        #expect(flowError["errorCode"] as? String == "network")
        #expect(flowError["source"] as? String == "events-test")
        #expect(flowError["message"] as? String == "diagnostic only")

        let flowInsights = try #require(flow["insights"] as? [String: Any])
        #expect(flowInsights["duration"] as? Int == 2_000)
        #expect(flowInsights["clicksCount"] as? Int == 2)
        #expect(flowInsights["authMethod"] as? String == "passkey")
        #expect(flowInsights["loggedIn"] as? Bool == true)
        #expect(flowInsights["registered"] as? Bool == false)

        let step = try #require((flow["steps"] as? [[String: Any]])?.first)
        #expect(step["operationType"] as? String == "PasskeyAuth")
        #expect(step["name"] as? String == "passkey")
        #expect(step["status"] as? String == "failed")
        #expect(step["startedAt"] as? String == "2024-01-01T00:00:01.123Z")
        #expect(step["completedAt"] as? String == "2024-01-01T00:00:01.623Z")

        let stepError = try #require((step["errors"] as? [[String: Any]])?.first)
        #expect(stepError["errorCode"] as? String == "timeout")
        #expect(stepError["source"] as? String == "passkey")
        #expect(stepError["message"] as? String == "timed out")

        let stepInsights = try #require(step["insights"] as? [String: Any])
        #expect(stepInsights["duration"] as? Int == 500)
        #expect(stepInsights["clicksCount"] as? Int == 2)
    }

    @Test func `Analytics enum wire values remain stable`() {
        let sources: [FlowInfo.Source] = [
            .widgetButton,
            .returningUserPrompt,
            .recoveryPrompt,
            .enrollPrompt,
            .elite,
            .agentAuthorizing,
            .deferred,
            .explicit,
            .implicit,
        ]

        #expect(
            Dictionary(uniqueKeysWithValues: sources.map { (String(describing: $0), $0.rawValue) }) == [
                "widgetButton": "widget-button",
                "returningUserPrompt": "returning-user-prompt",
                "recoveryPrompt": "recovery-prompt",
                "enrollPrompt": "enroll-prompt",
                "elite": "elite",
                "agentAuthorizing": "agent-authorizing",
                "deferred": "deferred",
                "explicit": "explicit",
                "implicit": "implicit",
            ]
        )
        #expect(
            Dictionary(uniqueKeysWithValues: InternalFlowStatus.allCases.map { (String(describing: $0), $0.rawValue) }) == [
                "aborted": "aborted",
                "inProgress": "in-progress",
                "completed": "completed",
                "switched": "switched",
                "failed": "failed",
            ]
        )
        #expect(
            Dictionary(uniqueKeysWithValues: InternalStepStatus.allCases.map { (String(describing: $0), $0.rawValue) }) == [
                "aborted": "aborted",
                "inProgress": "in-progress",
                "completed": "completed",
                "failed": "failed",
            ]
        )
        #expect(InternalEventInfoType.allCases.map(\.rawValue) == ["journey-summary"])
    }

    @Test func `Events maps non-bad-request HTTP failures to internal unexpected diagnostics`() throws {
        let forbidden = try makeCall().mapHttpError(httpError(statusCode: 403, body: ""))
        try assertUnexpectedAPIContractResponseError(forbidden, statusCode: 403)

        let unauthorized = try makeCall().mapHttpError(
            httpError(statusCode: 401, body: #"{"errorCode":"unauthorized","message":"Unauthorized"}"#)
        )
        try assertUnexpectedAPIContractResponseError(unauthorized, statusCode: 401)
    }

    @Test func `Events API maps payload construction failures to diagnostics without network request`() async throws {
        let network = APIRecordingNetwork()
        let api = EventsAPIImpl(
            apiBaseURL: StaticAPIBaseURL(url: baseURL),
            network: network,
            coder: ThrowingEventsJSONCoder(),
            interceptor: nil
        )

        let failure = try requireFailure(
            await api.start(params: EventsAPIParams(userJourney: userJourneySummary(), traceParent: traceParent))
        )

        try assertUnexpectedRuntimeError(failure)
        #expect(await network.requestCount() == 0)
    }

    @Test func `Events API maps base URL failures to diagnostics without network request`() async throws {
        let network = APIRecordingNetwork()
        let api = EventsAPIImpl(
            apiBaseURL: ThrowingEventsAPIBaseURL(),
            network: network,
            coder: coder,
            interceptor: nil
        )

        let failure = try requireFailure(
            await api.start(params: EventsAPIParams(userJourney: userJourneySummary(), traceParent: traceParent))
        )

        try assertUnexpectedRuntimeError(failure)
        #expect(await network.requestCount() == 0)
    }

    private func makeCall() throws -> EventsAPICall {
        try EventsAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            userJourney: userJourneySummary(),
            traceParent: traceParent
        )
    }

    private func httpError(statusCode: Int, body: String) -> NetworkResponse.Fail.HttpError {
        NetworkResponse.Fail.HttpError(
            url: baseURL.appendingPathComponent("event/journey"),
            statusCode: statusCode,
            headers: [:],
            body: body
        )
    }

    private func assertUnexpectedAPIContractResponseError(
        _ failure: EventsFailure,
        statusCode: Int,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        let apiUnexpectedError = try requireAPIUnexpectedError(failure, sourceLocation: sourceLocation)
        guard case .apiContract(let contract) = apiUnexpectedError.cause else {
            _ = try #require(nil as Void?, "Expected API contract cause, got \(apiUnexpectedError)", sourceLocation: sourceLocation)
            return
        }
        guard case .httpError(let responseError) = contract.failure else {
            _ = try #require(nil as Void?, "Expected HTTP error failure, got \(contract.failure)", sourceLocation: sourceLocation)
            return
        }

        #expect(responseError.statusCode == statusCode, sourceLocation: sourceLocation)
    }

    private func assertUnexpectedRuntimeError(
        _ failure: EventsFailure,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        let apiUnexpectedError = try requireAPIUnexpectedError(failure, sourceLocation: sourceLocation)
        guard case .runtime = apiUnexpectedError.cause else {
            _ = try #require(nil as Void?, "Expected runtime cause, got \(apiUnexpectedError)", sourceLocation: sourceLocation)
            return
        }
    }

    private func requireAPIUnexpectedError(
        _ failure: EventsFailure,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> APIUnexpectedError {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            return try #require(nil as APIUnexpectedError?, "Expected unexpected failure, got \(failure)", sourceLocation: sourceLocation)
        }
        #expect(errorCode == .unknown, sourceLocation: sourceLocation)

        return try #require(
            underlyingError as? APIUnexpectedError,
            "Expected APIUnexpectedError cause, got \(underlyingError)",
            sourceLocation: sourceLocation
        )
    }

    private func userJourneySummary() -> UserJourneySummary {
        UserJourneySummary(
            id: "journey-1",
            reporter: .init(
                service: .iosSdk,
                origin: "com.example.app",
                referer: "ios-app://com.example.app/login",
                version: "1.2.3"
            ),
            eventInfo: .init(
                type: .journeySummary,
                flows: [
                    FlowInfo(
                        id: "flow-1",
                        name: "boost-login",
                        source: .explicit,
                        status: .completed,
                        startedAt: Date(timeIntervalSince1970: 1_704_067_200.123),
                        completedAt: Date(timeIntervalSince1970: 1_704_067_202.123),
                        errors: [ClientError(errorCode: "network", source: "events-test", message: "diagnostic only")],
                        switchedToFlow: "flow-2",
                        insights: .init(
                            duration: 2_000,
                            errorRate: nil,
                            retries: nil,
                            clicksCount: 2,
                            authMethod: .passkey,
                            loggedIn: true,
                            registered: false
                        ),
                        steps: [
                            Step(
                                operationType: .passkeyAuth,
                                name: "passkey",
                                status: .failed,
                                startedAt: Date(timeIntervalSince1970: 1_704_067_201.123),
                                completedAt: Date(timeIntervalSince1970: 1_704_067_201.623),
                                errors: [ClientError(errorCode: "timeout", source: "passkey", message: "timed out")],
                                insights: .init(duration: 500, retries: nil, clicksCount: 2)
                            )
                        ]
                    )
                ]
            ),
            deviceInfo: .init(
                isPlatformAuthenticatorAvailable: true,
                isWebView: false,
                isMobileNative: true
            ),
            userInfo: [
                .init(
                    loginId: LoginID(id: "user@example.com", type: .email),
                    returningUser: true,
                    lastAuthMethod: .otp
                )
            ]
        )
    }

}

private struct ThrowingEventsJSONCoder: JSONCoder {
    var encoder: JSONEncoder { JSONEncoder() }
    var decoder: JSONDecoder { JSONDecoder() }

    func encodeToString<T: Encodable>(_ value: T) throws -> String {
        throw ThrowingEventsJSONCoderError.expected
    }

    func decodeFromString<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        throw ThrowingEventsJSONCoderError.expected
    }

    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        throw ThrowingEventsJSONCoderError.expected
    }

    func decodeFromJSONValue<T: Decodable>(_ element: JSONValue, as type: T.Type) throws -> T {
        throw ThrowingEventsJSONCoderError.expected
    }
}

private enum ThrowingEventsJSONCoderError: Error {
    case expected
}

private struct ThrowingEventsAPIBaseURL: APIBaseURL {
    func getBaseURL() throws -> URL {
        throw ThrowingEventsAPIBaseURLError.expected
    }
}

private enum ThrowingEventsAPIBaseURLError: Error {
    case expected
}
