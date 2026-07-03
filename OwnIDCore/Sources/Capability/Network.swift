import Foundation

/// HTTP networking capability used by the SDK.
///
/// Executes requests and returns ``NetworkResponse`` for expected outcomes; use ``NetworkRequest/RetryConfig`` to enable
/// retries for network errors.
///
/// Request and response bodies can contain tokens, login IDs, or other sensitive values. The default HTTP logger is
/// local-only and body logging is verbose-level only, but requests should call
/// ``NetworkRequest/setSuppressHttpLog(_:)`` for server-log uploads or any payload that should not appear in local
/// HTTP logs.
public protocol NetworkProtocol: Capability, Sendable {
    /// Executes `request` and returns a ``NetworkResponse``.
    ///
    /// When executed by the default network implementation, the outgoing `traceparent` header is rotated per send
    /// attempt (including retries). If the built request contains a valid `traceparent`, its `version`, `trace-id`,
    /// and `trace-flags` are preserved and only `parent-id` is regenerated for each attempt. If the header is missing
    /// or invalid, a new context is generated before send.
    ///
    /// - Returns: ``NetworkResponse`` with the success or failure outcome.
    /// - Throws: On unexpected transport-level errors (for example, task cancellation). Expected failures are returned
    ///   as ``NetworkResponse/fail(_:)``.
    func run(_ request: NetworkRequest) async throws -> NetworkResponse
}

/// Result of executing a network request.
public enum NetworkResponse: Sendable {
    /// A successful HTTP response (2xx).
    case success(Success)
    /// A failed HTTP response or transport error.
    case fail(Fail)

    /// A successful network response (2xx HTTP status).
    public struct Success: Sendable {
        /// The request URL.
        public let url: URL
        /// The HTTP status code.
        public let code: Int
        /// The HTTP response headers.
        public let headers: [String: String]
        /// The response body.
        public let body: String

        public init(url: URL, code: Int, headers: [String: String], body: String) {
            self.url = url
            self.code = code
            self.headers = headers
            self.body = body
        }
    }

    /// A failed network request.
    public enum Fail: Sendable, CustomStringConvertible {
        /// A non-2xx HTTP response (e.g. 4xx, 5xx).
        case httpError(HttpError)
        /// A transport-level connectivity error (e.g. timeout, no connection).
        case networkError(NetworkError)
        /// An unexpected error during the request (e.g. serialization, parsing).
        case responseError(ResponseError)

        /// A non-2xx HTTP response.
        public struct HttpError: Sendable {
            /// The request URL.
            public let url: URL
            /// The HTTP status code.
            public let statusCode: Int
            /// The HTTP response headers.
            public let headers: [String: String]
            /// The response body.
            public let body: String

            public init(url: URL, statusCode: Int, headers: [String: String], body: String) {
                self.url = url
                self.statusCode = statusCode
                self.headers = headers
                self.body = body
            }
        }

        /// A network connectivity error (e.g. timeout, no connection). Retrying is recommended.
        public struct NetworkError: Sendable {
            /// The request URL.
            public let url: URL
            /// The underlying `URLError`.
            public let error: URLError

            public init(url: URL, error: URLError) {
                self.url = url
                self.error = error
            }
        }

        /// An unexpected error during the request (e.g. serialization, parsing).
        public struct ResponseError: Sendable {
            /// The request URL.
            public let url: URL
            /// The HTTP status code, if an HTTP response was available.
            public let statusCode: Int?
            /// The underlying error.
            public let error: (any Swift.Error & Sendable)
            /// The HTTP response headers.
            public let headers: [String: String]
            /// The response body, if available.
            public let body: String?

            public init(url: URL, statusCode: Int?, error: any Swift.Error, headers: [String: String], body: String?) {
                self.url = url
                self.statusCode = statusCode
                self.error = error as NSError
                self.headers = headers
                self.body = body
            }
        }

        public var description: String {
            switch self {
            case .httpError(let e): return "HttpError(statusCode=\(e.statusCode))"
            case .networkError(let e): return "NetworkError(error=\(e.error))"
            case .responseError(let e): return "ResponseError(statusCode=\(String(describing: e.statusCode)), error=\(e.error))"
            }
        }
    }
}

/// Represents an HTTP request that can be executed by the network layer.
public struct NetworkRequest: Sendable {

    /// HTTP method.
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    /// Well-known HTTP header names used by the SDK.
    public enum Header: String, Sendable {
        case contentType = "Content-Type"
        case accept = "Accept"
        case authorization = "Authorization"
        case cacheControl = "Cache-Control"
        case acceptLanguage = "Accept-Language"
        case baggage = "Baggage"
        case traceparent = "traceparent"
        case ownIDAppURL = "X-OwnID-AppUrl"
    }

    private static let defaultHeaders: [String: String] = [
        Header.accept.rawValue: "application/json",
        Header.cacheControl.rawValue: "no-store",
    ]

    // A lightweight protocol to adapt/mutate outgoing URLRequests before sending.
    internal protocol Adapter: Sendable {
        func adapt(_ request: URLRequest) async -> URLRequest
    }

    internal struct AdapterChain: Sendable {
        private let adapters: [any Adapter]

        internal init(adapters: [any Adapter]) { self.adapters = adapters }

        internal func adapt(_ request: URLRequest) async -> URLRequest {
            var result = request
            for adapter in adapters {
                result = await adapter.adapt(result)
            }
            return result
        }
    }

    private static let defaultJSONWithCharset = "application/json; charset=utf-8"

    /// Retry configuration for network calls.
    ///
    /// Only retriable ``NetworkResponse/Fail/networkError(_:)`` values are retried. Cancellation, timeouts,
    /// HTTP errors, and response-processing errors are returned or thrown as-is. Defaults to 0 retries, 250 ms initial
    /// delay, a 2.0 factor, and a 1000 ms max delay.
    public struct RetryConfig: Sendable, Equatable {
        /// Number of retries.
        public let retries: Int
        /// Initial backoff delay in milliseconds.
        public let initialDelayMilliseconds: Int
        /// Multiplicative factor for exponential backoff.
        public let factor: Double
        /// Upper bound for backoff delay in milliseconds.
        public let maxDelayMilliseconds: Int

        public init(retries: Int = 0, initialDelayMilliseconds: Int = 250, factor: Double = 2.0, maxDelayMilliseconds: Int = 1_000) {
            self.retries = retries
            self.initialDelayMilliseconds = initialDelayMilliseconds
            self.factor = factor
            self.maxDelayMilliseconds = maxDelayMilliseconds
        }

        public static let `default` = RetryConfig(retries: 0, initialDelayMilliseconds: 250, factor: 2.0, maxDelayMilliseconds: 1_000)
    }

    internal private(set) var url: URL
    internal private(set) var method: Method = .post
    private var headers: [String: String] = [:]
    private var bodyString: String = "{}"
    private var cachePolicy: URLRequest.CachePolicy?
    private var allowCaching: Bool = false
    internal var suppressHttpLog: Bool = false

    /// Creates a request targeting the given URL (defaults to POST with an empty JSON body).
    public init(url: URL) {
        self.url = url
    }

    /// Sets the HTTP method.
    public mutating func setMethod(_ method: Method) {
        self.method = method
    }

    /// Sets (or replaces) a header value.
    public mutating func setHeader(name: String, value: String) {
        headers[name] = value
    }

    /// Sets a header value only if the header is not already present.
    public mutating func setHeaderIfAbsent(name: String, value: String) {
        if headers[name] == nil {
            headers[name] = value
        }
    }

    /// Sets the request body (used for POST).
    public mutating func setBody(_ jsonString: String) {
        bodyString = jsonString
    }

    /// Suppresses local HTTP logging for this request; defaults to `true`.
    ///
    /// Suppression affects the SDK's local HTTP logger only. It does not change network execution, response mapping,
    /// server-side API failure logging, or app-owned logging.
    public mutating func setSuppressHttpLog(_ value: Bool = true) {
        suppressHttpLog = value
    }

    /// Overrides the default cache policy for this request.
    public mutating func setCachePolicy(_ policy: URLRequest.CachePolicy) {
        cachePolicy = policy
    }

    /// Allows the response to be cached (removes the default `no-store` header); defaults to `true`.
    public mutating func setAllowCaching(_ value: Bool = true) {
        allowCaching = value
    }

    internal mutating func addToRequest(accessToken: AccessToken?) {
        guard let accessToken = accessToken else { return }
        headers[Header.authorization.rawValue] = "Bearer \(accessToken.token)"
    }

    /// Builds the final `URLRequest` with all configured headers, method, and body.
    ///
    /// This function creates a request template. The default ``NetworkProtocol`` implementation may overwrite the
    /// outbound `traceparent` value before each send attempt.
    public func buildURLRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let cachePolicy {
            request.cachePolicy = cachePolicy
        }

        var applied: [String: String] = Self.defaultHeaders
        if allowCaching {
            applied.removeValue(forKey: Header.cacheControl.rawValue)
        }
        for (k, v) in headers { applied[k] = v }

        if method == .post {
            if applied[Header.contentType.rawValue] == nil {
                applied[Header.contentType.rawValue] = Self.defaultJSONWithCharset
            }
            request.httpBody = bodyString.data(using: .utf8)
        }

        for (name, value) in applied {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return request
    }
}

extension NetworkRequest {
    internal struct DefaultHeadersAdapter: Adapter {
        private let localInfo: any LocalInfo
        private let appURLHeaderValue: String
        private let tagsCache: LanguageTagsCache

        private actor LanguageTagsCache {
            private var latest: [LanguageTag] = [LanguageTag.default]

            fileprivate init(provider: any LanguageTagsProvider) {
                Task { [weak self] in
                    guard let self else { return }
                    for await tags in provider.languageTags {
                        await self.update(tags)
                    }
                }
            }

            fileprivate func current() -> [LanguageTag] { latest }

            fileprivate func update(_ tags: [LanguageTag]) {
                latest = tags
            }
        }

        internal init(localInfo: any LocalInfo, languageTagsProvider: any LanguageTagsProvider, appURLHeaderValue: String) {
            self.localInfo = localInfo
            self.appURLHeaderValue = appURLHeaderValue
            self.tagsCache = LanguageTagsCache(provider: languageTagsProvider)
        }

        func adapt(_ request: URLRequest) async -> URLRequest {
            var req = request

            if req.value(forHTTPHeaderField: Header.acceptLanguage.rawValue) == nil {
                let tags = await tagsCache.current()
                let joined = tags.map { $0.tagString }.joined(separator: ",")
                let value = joined.isEmpty ? "en" : joined
                req.setValue(value, forHTTPHeaderField: Header.acceptLanguage.rawValue)
            }

            if req.value(forHTTPHeaderField: Header.ownIDAppURL.rawValue) == nil {
                req.setValue(appURLHeaderValue, forHTTPHeaderField: Header.ownIDAppURL.rawValue)
            }

            let baggagePair = "sdk.correlation_id=\(localInfo.correlationId)"
            let existingBaggage = req.value(forHTTPHeaderField: Header.baggage.rawValue) ?? ""
            let tokens = existingBaggage.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let hasCorrelation = tokens.contains { $0.lowercased().hasPrefix("sdk.correlation_id=") }
            let merged: String = {
                if tokens.isEmpty { return baggagePair }
                if hasCorrelation { return tokens.joined(separator: ",") }
                return (tokens + [baggagePair]).joined(separator: ",")
            }()
            req.setValue(merged, forHTTPHeaderField: Header.baggage.rawValue)

            return req
        }
    }
}
