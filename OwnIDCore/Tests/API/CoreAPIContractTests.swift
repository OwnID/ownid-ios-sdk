import Foundation
import Testing

@testable import OwnIDCore

struct CoreAPIContractTests {
    private let baseURL = URL(string: "https://example.test/api")!

    @Test func `API result helpers only run matching branches and preserve cancellation`() {
        var events: [String] = []

        let success = APIResult<Int, TestFailure>.success(7)
            .onSuccess { events.append("success:\($0)") }
            .onError { events.append("error:\($0.message)") }
            .onCanceled { events.append("canceled") }

        #expect(events == ["success:7"])
        #expect(success.getOrNil() == 7)
        #expect(success.errorOrNil() == nil)
        #expect(success.map { "value:\($0)" }.getOrNil() == "value:7")
        #expect(success.fold(onSuccess: { "success:\($0)" }, onError: { "error:\($0.message)" }, onCanceled: { "canceled" }) == "success:7")
        #expect(success.description == "Success")

        let failure = APIResult<Int, TestFailure>.failure(TestFailure(message: "denied"))
            .onSuccess { events.append("unexpected-success:\($0)") }
            .onError { events.append("error:\($0.message)") }
            .onCanceled { events.append("unexpected-canceled") }

        #expect(events == ["success:7", "error:denied"])
        #expect(failure.getOrNil() == nil)
        #expect(failure.errorOrNil() == TestFailure(message: "denied"))
        #expect(failure.mapError { $0.message.uppercased() }.errorOrNil() == "DENIED")
        #expect(
            failure.fold(onSuccess: { "success:\($0)" }, onError: { "error:\($0.message)" }, onCanceled: { "canceled" }) == "error:denied"
        )
        #expect(failure.description == "Failure(failure=TestFailure(message: denied))")

        let canceled = APIResult<Int, TestFailure>.canceled
            .onSuccess { events.append("unexpected-success:\($0)") }
            .onError { events.append("unexpected-error:\($0.message)") }
            .onCanceled { events.append("canceled") }

        #expect(events == ["success:7", "error:denied", "canceled"])
        #expect(canceled.isCanceled)
        #expect(canceled.getOrNil() == nil)
        #expect(canceled.errorOrNil() == nil)
        #expect(canceled.map { "\($0)" }.isCanceled)
        #expect(canceled.mapError { $0.message }.isCanceled)
        #expect(canceled.fold(onSuccess: { "success:\($0)" }, onError: { "error:\($0.message)" }, onCanceled: { "canceled" }) == "canceled")
        #expect(canceled.description == "Canceled")
    }

    @Test func `API failure scope wire values are exhaustive`() {
        #expect(APIFailureScope.allCases.map(\.rawValue) == ["data", "channel", "session"])
    }

    @Test(arguments: APIFailureScope.allCases)
    func `API failure scope codable round trips stable wire values`(_ scope: APIFailureScope) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        #expect(try encodedString(scope, encoder: encoder) == #""\#(scope.rawValue)""#)
        #expect(try decoder.decode(APIFailureScope.self, from: Data(#""\#(scope.rawValue)""#.utf8)) == scope)
    }

    @Test func `API failure scope decoding rejects unknown wire values`() {
        let decoder = JSONDecoder()

        #expect(throws: (any Error).self) { try decoder.decode(APIFailureScope.self, from: Data(#""provider""#.utf8)) }
    }

    @Test func `Public API params defaults and explicit values`() throws {
        #expect(DiscoverAPIParams().loginID == nil)
        #expect(LoginAPIParams().accessToken == nil)

        let loginID = LoginID(id: "user@example.com", type: .email)
        #expect(DiscoverAPIParams(loginID: loginID).loginID == loginID)

        let accessToken = AccessToken(token: "access-token")
        #expect(LoginAPIParams(accessToken: accessToken).accessToken == accessToken)

        let defaultOIDCParams = OIDCAPIParams()
        #expect(defaultOIDCParams.provider == nil)
        try assertOAuthResponseType(defaultOIDCParams.oauthResponseType, is: .idToken)
        #expect(defaultOIDCParams.accessToken == nil)

        let explicitOIDCParams = OIDCAPIParams(provider: .google, oauthResponseType: .code, accessToken: accessToken)
        #expect(explicitOIDCParams.provider == .google)
        try assertOAuthResponseType(explicitOIDCParams.oauthResponseType, is: .code)
        #expect(explicitOIDCParams.accessToken == accessToken)
    }

    @Test func `API call execute maps transport success`() async throws {
        var request = NetworkRequest(url: baseURL.appendingPathComponent("execute-success"))
        request.setHeader(name: "X-Test", value: "success")
        let network = APIRecordingNetwork(
            response: .success(
                NetworkResponse.Success(url: baseURL, code: 201, headers: ["X-Result": "ok"], body: "created")
            )
        )

        let value = try requireSuccess(try await TestAPICall().execute(network: network, request: request))

        #expect(value == "success:201:created")
        let requestURLs = await network.requestURLs()
        #expect(requestURLs == [baseURL.appendingPathComponent("execute-success")])
    }

    @Test func `API call execute maps HTTP error failure`() async throws {
        let network = APIRecordingNetwork(
            response: .fail(
                .httpError(
                    NetworkResponse.Fail.HttpError(url: baseURL, statusCode: 418, headers: [:], body: "teapot")
                )
            )
        )

        let failure = try requireFailure(try await TestAPICall().execute(network: network, request: NetworkRequest(url: baseURL)))

        #expect(failure == .http(statusCode: 418, body: "teapot"))
    }

    @Test func `API call execute maps network and response failures as unhandled`() async throws {
        let networkError = APIRecordingNetwork(
            response: .fail(.networkError(NetworkResponse.Fail.NetworkError(url: baseURL, error: URLError(.notConnectedToInternet))))
        )
        let networkFailure = try requireFailure(
            try await TestAPICall().execute(network: networkError, request: NetworkRequest(url: baseURL))
        )
        #expect(networkFailure == .network)

        let responseError = APIRecordingNetwork(
            response: .fail(
                .responseError(
                    NetworkResponse.Fail.ResponseError(
                        url: baseURL,
                        statusCode: 200,
                        error: NSError(domain: "CoreAPIContractTests", code: 1),
                        headers: [:],
                        body: nil
                    )
                )
            )
        )
        let responseFailure = try requireFailure(
            try await TestAPICall().execute(network: responseError, request: NetworkRequest(url: baseURL))
        )
        #expect(responseFailure == .response)
    }

    @Test func `API call execute rethrows cancellation`() async throws {
        let cancellation = APIThrowingNetwork(error: CancellationError())
        await #expect(throws: CancellationError.self) {
            _ = try await TestAPICall().execute(network: cancellation, request: NetworkRequest(url: baseURL))
        }

        let urlCancellation = APIThrowingNetwork(error: URLError(.cancelled))
        await #expect(throws: CancellationError.self) {
            _ = try await TestAPICall().execute(network: urlCancellation, request: NetworkRequest(url: baseURL))
        }
    }

    private func encodedString<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        return try #require(String(data: data, encoding: .utf8))
    }

    private func assertOAuthResponseType(
        _ actual: OAuthResponseType,
        is expected: OAuthResponseType,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        switch (actual, expected) {
        case (.code, .code), (.idToken, .idToken):
            return
        default:
            _ = try #require(nil as Void?, "Expected \(expected), got \(actual)", sourceLocation: sourceLocation)
        }
    }

}

private struct TestFailure: Sendable, Equatable, CustomStringConvertible {
    let message: String

    var description: String {
        "TestFailure(message: \(message))"
    }
}

private enum TestAPICallFailure: Sendable, Equatable, CustomStringConvertible {
    case http(statusCode: Int, body: String)
    case network
    case response
    case other

    var description: String {
        switch self {
        case .http(let statusCode, let body): return "http(statusCode: \(statusCode), body: \(body))"
        case .network: return "network"
        case .response: return "response"
        case .other: return "other"
        }
    }
}

private struct TestAPICall: APICall {
    let request = NetworkRequest(url: URL(string: "https://example.test/default")!)

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<String, TestAPICallFailure> {
        .success("success:\(successResponse.code):\(successResponse.body)")
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> TestAPICallFailure {
        .http(statusCode: failResponse.statusCode, body: failResponse.body)
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> TestAPICallFailure {
        switch failResponse {
        case .networkError:
            return .network
        case .responseError:
            return .response
        case .httpError:
            return .other
        }
    }
}
