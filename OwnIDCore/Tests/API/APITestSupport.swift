import Foundation
import Testing

@testable import OwnIDCore

struct StaticAPIBaseURL: APIBaseURL {
    let url: URL

    func getBaseURL() throws -> URL {
        url
    }
}

final class APIUnusedNetwork: NetworkProtocol, @unchecked Sendable {
    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        throw URLError(.badServerResponse)
    }
}

struct APIThrowingNetwork: NetworkProtocol {
    let error: any Error & Sendable

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        throw error
    }
}

actor APIRecordingNetwork: NetworkProtocol {
    enum ExhaustedResponse {
        case networkError(URLError.Code)
        case responseError(message: String)
        case suspendUntilCancellation
    }

    private struct RequestCountWaiter {
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var responses: [NetworkResponse]
    private let repeatsLastResponse: Bool
    private let exhaustedResponse: ExhaustedResponse
    private var requests: [NetworkRequest] = []
    private var requestCountWaiters: [RequestCountWaiter] = []

    init(
        responses: [NetworkResponse] = [],
        exhaustedResponse: ExhaustedResponse = .networkError(.badServerResponse)
    ) {
        self.responses = responses
        self.repeatsLastResponse = false
        self.exhaustedResponse = exhaustedResponse
    }

    init(
        response: NetworkResponse,
        exhaustedResponse: ExhaustedResponse = .networkError(.badServerResponse)
    ) {
        self.responses = [response]
        self.repeatsLastResponse = true
        self.exhaustedResponse = exhaustedResponse
    }

    init(suspendingAfter responses: [NetworkResponse] = []) {
        self.responses = responses
        self.repeatsLastResponse = false
        self.exhaustedResponse = .suspendUntilCancellation
    }

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        requests.append(request)
        resumeReadyRequestCountWaiters()

        if responses.count > 1 {
            return responses.removeFirst()
        }
        if let response = responses.first {
            if repeatsLastResponse {
                return response
            }
            return responses.removeFirst()
        }

        switch exhaustedResponse {
        case .networkError(let code):
            return .fail(.networkError(.init(url: request.url, error: URLError(code))))
        case .responseError(let message):
            let error = NSError(domain: "OwnID.Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            return .fail(.responseError(.init(url: request.url, statusCode: nil, error: error, headers: [:], body: nil)))
        case .suspendUntilCancellation:
            try await APICancellationWaiter().wait()
            throw CancellationError()
        }
    }

    func requestCount() -> Int {
        requests.count
    }

    func request(at index: Int) -> NetworkRequest? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }

    func requestURLs() -> [URL] {
        requests.map(\.url)
    }

    func requestPaths() -> [String] {
        requests.map(\.url.path)
    }

    func endpointPaths(suffixComponentCount: Int) -> [String] {
        requests.map { $0.url.pathComponents.suffix(suffixComponentCount).joined(separator: "/") }
    }

    func requestsSnapshot() -> [NetworkRequest] {
        requests
    }

    func onlyURLRequest(
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> URLRequest? {
        try #require(requests.count <= 1, "Expected at most one request, got \(requests.count)", sourceLocation: sourceLocation)
        return requests.first?.buildURLRequest()
    }

    func waitForRequestCount(
        _ count: Int,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async {
        if requests.count >= count { return }

        await withCheckedContinuation { continuation in
            if requests.count >= count {
                continuation.resume()
            } else {
                requestCountWaiters.append(
                    RequestCountWaiter(minimumCount: count, continuation: continuation)
                )
            }
        }

        #expect(requests.count >= count, "Expected at least \(count) API request(s)", sourceLocation: sourceLocation)
    }

    private func resumeReadyRequestCountWaiters() {
        let currentCount = requests.count
        let readyWaiters = requestCountWaiters.filter { currentCount >= $0.minimumCount }
        requestCountWaiters.removeAll { currentCount >= $0.minimumCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }
}

private final class APICancellationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var isCancelled = false

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldResume: Bool = lock.withLock {
                    guard !isCancelled else { return true }
                    self.continuation = continuation
                    return false
                }
                if shouldResume {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            cancel()
        }
    }

    private func cancel() {
        let continuation = lock.withLock {
            isCancelled = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}

func bodyObject(
    from request: URLRequest,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> [String: Any] {
    let body = try #require(request.httpBody, sourceLocation: sourceLocation)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any], sourceLocation: sourceLocation)
}

func requireSuccess<Success, Failure>(
    _ result: APIResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Success {
    guard case .success(let value) = result else {
        return try #require(nil as Success?, "Expected success, got \(result)", sourceLocation: sourceLocation)
    }

    return value
}

func requireFailure<Success, Failure>(
    _ result: APIResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Failure {
    guard case .failure(let failure) = result else {
        return try #require(nil as Failure?, "Expected failure, got \(result)", sourceLocation: sourceLocation)
    }

    return failure
}

func assertAPIUnexpectedResponseError(
    errorCode: ErrorCode,
    underlyingError: any Error & Sendable,
    statusCode: Int,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
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
}
