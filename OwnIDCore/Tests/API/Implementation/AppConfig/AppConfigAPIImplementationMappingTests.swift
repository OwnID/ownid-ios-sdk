import Foundation
import Testing

@testable import OwnIDCore

struct AppConfigAPIImplementationMappingTests {
    private let baseURL = URL(string: "https://example.test/api")!
    private let coder = JSONCoderImpl()

    @Test func `Request builds config endpoint and trace header`() throws {
        let call = try AppConfigAPICall(
            apiBaseURL: baseURL,
            coder: coder,
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )

        let request = call.request.buildURLRequest()

        #expect(request.url == baseURL.appendingPathComponent("config/app"))
        #expect(request.httpMethod == "GET")
        #expect(
            request.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue)
                == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
        )
        #expect(request.httpBody == nil)
    }

    @Test func `Maps app auth config success response`() throws {
        let result = try makeCall().mapHttpSuccess(
            success(
                code: 200,
                body: """
                    {
                      "displayName": "Example App",
                      "loginIdConfig": [
                        {"type": "Email", "regex": "^[^@]+@example\\\\.test$"},
                        {"type": "PhoneNumber"}
                      ],
                      "webView": {
                        "baseUrl": "https://app.example.test",
                        "html": "<html></html>",
                        "allowedOrigins": ["https://one.example.test", "https://two.example.test"]
                      },
                      "ui": {
                        "default": {"logoUrl": "https://cdn.example.test/default.png"},
                        "dark": {"logoUrl": "https://cdn.example.test/dark.png"}
                      },
                      "logLevel": "Debug"
                    }
                    """
            )
        )

        let config = try requireSuccess(result)

        #expect(
            config.loginIdConfig == [
                AppConfig.LoginIdConfig(type: .email, regex: #"^[^@]+@example\.test$"#),
                AppConfig.LoginIdConfig(type: .phoneNumber, regex: nil),
            ]
        )
        #expect(config.displayName == "Example App")
        #expect(config.webView?.baseUrl == "https://app.example.test")
        #expect(config.webView?.html == "<html></html>")
        #expect(config.webView?.allowedOrigins == ["https://one.example.test", "https://two.example.test"])
        #expect(config.ui?.default.logoUrl == "https://cdn.example.test/default.png")
        #expect(config.ui?.dark?.logoUrl == "https://cdn.example.test/dark.png")
        #expect(config.logLevel == .debug)
    }

    @Test func `Maps missing log level to warning fallback`() throws {
        let result = try makeCall().mapHttpSuccess(
            success(code: 200, body: #"{"loginIdConfig":[{"type":"Email"}]}"#)
        )

        let config = try requireSuccess(result)

        #expect(config.loginIdConfig == [AppConfig.LoginIdConfig(type: .email, regex: nil)])
        #expect(config.displayName == nil)
        #expect(config.webView == nil)
        #expect(config.ui == nil)
        #expect(config.logLevel == .warning)
    }

    @Test func `Maps bad-request DTO failures`() throws {
        let invalidArgument = try makeCall().mapHttpError(
            httpError(
                statusCode: 400,
                body: #"{"errorCode":"invalid_argument","message":"App ID is invalid"}"#
            )
        )
        try assertBadRequest(invalidArgument, errorCode: .invalidArgument, message: "App ID is invalid")

        let unknown = try makeCall().mapHttpError(
            httpError(
                statusCode: 400,
                body: #"{"errorCode":"unknown","message":"Config request failed"}"#
            )
        )
        try assertBadRequest(unknown, errorCode: .unknown, message: "Config request failed")
    }

    @Test func `Maps non-bad-request HTTP failures to internal unexpected diagnostics`() throws {
        let blankForbidden = try makeCall().mapHttpError(httpError(statusCode: 403, body: ""))
        try assertUnexpectedAPIContractHTTPError(blankForbidden, statusCode: 403)

        let unauthorized = try makeCall().mapHttpError(
            httpError(statusCode: 401, body: #"{"errorCode":"unauthorized","message":"Unauthorized"}"#)
        )
        try assertUnexpectedAPIContractHTTPError(unauthorized, statusCode: 401)
    }

    @Test func `Maps unexpected success status and malformed body to unexpected failures`() throws {
        let unexpectedStatus = try requireFailure(try makeCall().mapHttpSuccess(success(code: 204, body: "")))
        try assertUnexpectedAPIContractResponseError(unexpectedStatus, statusCode: 204)

        let malformedBody = try requireFailure(
            try makeCall().mapHttpSuccess(success(code: 200, body: #"{"displayName":"Missing required loginIdConfig"}"#))
        )
        try assertUnexpectedAPIContractResponseError(malformedBody, statusCode: 200) { responseError in
            let error = responseError.error as NSError
            #expect(error.userInfo[NSUnderlyingErrorKey] is DecodingError)
        }
    }

    private func makeCall() throws -> AppConfigAPICall {
        try AppConfigAPICall(apiBaseURL: baseURL, coder: coder, traceParent: nil)
    }

    private func success(code: Int, body: String) -> NetworkResponse.Success {
        NetworkResponse.Success(url: baseURL.appendingPathComponent("config/app"), code: code, headers: [:], body: body)
    }

    private func httpError(statusCode: Int, body: String) -> NetworkResponse.Fail.HttpError {
        NetworkResponse.Fail.HttpError(
            url: baseURL.appendingPathComponent("config/app"),
            statusCode: statusCode,
            headers: [:],
            body: body
        )
    }

    private func assertBadRequest(
        _ failure: AppConfigFailure,
        errorCode: ErrorCode,
        message: String,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        switch failure {
        case .badRequest(let actualCode, let actualMessage):
            #expect(actualCode == errorCode, sourceLocation: sourceLocation)
            #expect(actualMessage == message, sourceLocation: sourceLocation)
        default:
            _ = try #require(nil as Void?, "Expected bad request failure, got \(failure)", sourceLocation: sourceLocation)
        }
    }

    private func assertUnexpectedAPIContractResponseError(
        _ failure: AppConfigFailure,
        statusCode: Int,
        responseErrorAssertions: (NetworkResponse.Fail.ResponseError) -> Void = { _ in },
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            _ = try #require(nil as Void?, "Expected unexpected failure, got \(failure)", sourceLocation: sourceLocation)
            return
        }
        #expect(errorCode == .unknown, sourceLocation: sourceLocation)

        let apiUnexpectedError = try #require(
            underlyingError as? APIUnexpectedError,
            "Expected APIUnexpectedError cause, got \(underlyingError)",
            sourceLocation: sourceLocation
        )
        guard case .apiContract(let contract) = apiUnexpectedError.cause else {
            _ = try #require(nil as Void?, "Expected API contract cause, got \(apiUnexpectedError)", sourceLocation: sourceLocation)
            return
        }
        guard case .responseError(let responseError) = contract.failure else {
            _ = try #require(nil as Void?, "Expected response error failure, got \(contract.failure)", sourceLocation: sourceLocation)
            return
        }

        #expect(responseError.statusCode == statusCode, sourceLocation: sourceLocation)
        responseErrorAssertions(responseError)
    }

    private func assertUnexpectedAPIContractHTTPError(
        _ failure: AppConfigFailure,
        statusCode: Int,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        guard case .unexpected(let errorCode, _, let underlyingError) = failure else {
            _ = try #require(nil as Void?, "Expected unexpected failure, got \(failure)", sourceLocation: sourceLocation)
            return
        }
        #expect(errorCode == .unknown, sourceLocation: sourceLocation)

        let apiUnexpectedError = try #require(
            underlyingError as? APIUnexpectedError,
            "Expected APIUnexpectedError cause, got \(underlyingError)",
            sourceLocation: sourceLocation
        )
        guard case .apiContract(let contract) = apiUnexpectedError.cause else {
            _ = try #require(nil as Void?, "Expected API contract cause, got \(apiUnexpectedError)", sourceLocation: sourceLocation)
            return
        }
        guard case .httpError(let httpError) = contract.failure else {
            _ = try #require(nil as Void?, "Expected HTTP error failure, got \(contract.failure)", sourceLocation: sourceLocation)
            return
        }

        #expect(httpError.statusCode == statusCode, sourceLocation: sourceLocation)
    }

}
