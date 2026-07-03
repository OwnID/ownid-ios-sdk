import Foundation

/// Default ``NetworkProtocol`` implementation backed by the configured `URLSession`.
///
/// The implementation returns typed ``NetworkResponse`` values for successful HTTP responses, non-2xx responses, and
/// expected transport failures. Task cancellation cancels the active request and remains cancellation, not a provider
/// failure value. When retry configuration is present, only recoverable network failures are retried.
internal actor NetworkImpl: NetworkProtocol {
    internal typealias RetrySleeper = @Sendable (UInt64) async throws -> Void

    private let urlSession: URLSession
    private let requestAdapters: NetworkRequest.AdapterChain?
    private let retryConfig: NetworkRequest.RetryConfig?
    private let httpLogger: HTTPLogger?
    private let retrySleeper: RetrySleeper

    internal init(
        urlSession: URLSession,
        requestAdapters: NetworkRequest.AdapterChain? = nil,
        retryConfig: NetworkRequest.RetryConfig? = nil,
        httpLogger: HTTPLogger? = nil,
        retrySleeper: @escaping RetrySleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.urlSession = urlSession
        self.requestAdapters = requestAdapters
        self.retryConfig = retryConfig
        self.httpLogger = httpLogger
        self.retrySleeper = retrySleeper
    }

    internal func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        let baseRequest = request.buildURLRequest()
        let baseSendRequest = await requestAdapters?.adapt(baseRequest) ?? baseRequest
        let traceSeed = TraceContext.resolveSeed(baseSendRequest.value(forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue))
        let makeAttemptRequest: @Sendable () -> URLRequest = {
            var requestForAttempt = baseSendRequest
            requestForAttempt.setValue(
                TraceContext.nextTraceParent(seed: traceSeed),
                forHTTPHeaderField: NetworkRequest.Header.traceparent.rawValue
            )
            return requestForAttempt
        }
        let suppress = request.suppressHttpLog
        if let retry = retryConfig {
            return try await performWithRetry(
                url: request.url,
                makeAttemptRequest: makeAttemptRequest,
                retry: retry,
                suppressHttpLog: suppress
            )
        } else {
            return try await performRequestOnce(url: request.url, urlRequest: makeAttemptRequest(), suppressHttpLog: suppress)
        }
    }

    private func performWithRetry(
        url: URL,
        makeAttemptRequest: @Sendable () -> URLRequest,
        retry: NetworkRequest.RetryConfig,
        suppressHttpLog: Bool
    ) async throws -> NetworkResponse {
        var attempt = 0
        var delayMs = Double(retry.initialDelayMilliseconds)
        let maxDelay = Double(retry.maxDelayMilliseconds)

        while true {
            try Task.checkCancellation()
            let result = try await performRequestOnce(url: url, urlRequest: makeAttemptRequest(), suppressHttpLog: suppressHttpLog)
            switch result {
            case .success:
                return result

            case .fail(let error):
                if case .networkError(let net) = error, isRetriable(urlError: net.error), attempt < retry.retries {
                    attempt += 1
                    let ns = UInt64((delayMs / 1000.0) * 1_000_000_000)
                    try await retrySleeper(ns)
                    delayMs = min(delayMs * retry.factor, maxDelay)
                    continue
                }
                return result
            }
        }
    }

    private func isRetriable(urlError: URLError) -> Bool {
        if urlError.code == .cancelled { return false }
        if urlError.code == .timedOut { return false }
        switch urlError.code {
        case .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed,
            .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    private func performRequestOnce(url: URL, urlRequest: URLRequest, suppressHttpLog: Bool) async throws -> NetworkResponse {
        let start = DispatchTime.now()
        if !suppressHttpLog { httpLogger?.logRequest(urlRequest) }

        do {
            let (data, urlResponse) = try await urlSession.dataCompat(for: urlRequest)

            let end = DispatchTime.now()
            let tookMs = Int(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
            if !suppressHttpLog {
                httpLogger?.logResponse(request: urlRequest, response: urlResponse, data: data, error: nil, tookMs: tookMs)
            }

            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                return .fail(.responseError(.init(url: url, statusCode: nil, error: URLError(.badServerResponse), headers: [:], body: nil)))
            }

            var headers: [String: String] = [:]
            for (k, v) in httpResponse.allHeaderFields {
                let key = String(describing: k).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                headers[key] = val
            }

            let bodyString = String(data: data, encoding: .utf8) ?? ""

            if (200...299).contains(httpResponse.statusCode) {
                return .success(.init(url: url, code: httpResponse.statusCode, headers: headers, body: bodyString))
            } else {
                return .fail(.httpError(.init(url: url, statusCode: httpResponse.statusCode, headers: headers, body: bodyString)))
            }
        } catch {
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled { throw CancellationError() }
            let end = DispatchTime.now()
            let tookMs = Int(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
            if !suppressHttpLog { httpLogger?.logResponse(request: urlRequest, response: nil, data: nil, error: error, tookMs: tookMs) }

            if let urlError = error as? URLError {
                return .fail(.networkError(.init(url: url, error: urlError)))
            } else {
                return .fail(.responseError(.init(url: url, statusCode: nil, error: error, headers: [:], body: nil)))
            }
        }
    }
}

extension URLSession {
    internal func dataCompat(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        if #available(iOS 15, *) {
            return try await data(for: request, delegate: delegate)
        }

        let taskHolder = URLSessionTaskHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = dataTask(with: request) { data, response, error in
                    taskHolder.clear()
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                taskHolder.set(task)
                task.resume()
            }
        } onCancel: {
            taskHolder.cancel()
        }
    }
}

private final class URLSessionTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCanceled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        if isCanceled {
            lock.unlock()
            task.cancel()
            return
        }
        self.task = task
        lock.unlock()
    }

    func clear() {
        lock.lock()
        task = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCanceled = true
        let current = task
        task = nil
        lock.unlock()
        current?.cancel()
    }
}
