import Foundation

/// Mirrors SDK HTTP traffic into the configured local logger only.
///
/// The default network implementation receives an HTTP logger only when the configured ``OwnIDLogger`` accepts
/// ``LogLevel/debug``. Debug logs request/response lines. Verbose additionally logs all request/response headers and
/// bodies that appear to be UTF-8; binary bodies are omitted. Requests marked to suppress HTTP logging are skipped by
/// the network layer, including server diagnostic posts.
///
/// Verbose output includes header values and UTF-8 bodies as present in the request or response.
internal final class HTTPLogger {
    private let logger: any OwnIDLogger

    internal init(logger: any OwnIDLogger) { self.logger = logger }

    private var isEnabled: Bool { logger.isEnabled(.debug) }
    private var doBody: Bool { logger.isEnabled(.verbose) }

    internal func logRequest(_ request: URLRequest) {
        guard isEnabled else { return }

        let lineLevel: LogLevel = doBody ? .verbose : .debug

        var lines: [String] = []
        let method = request.httpMethod ?? "GET"
        let urlStr = request.url?.absoluteString ?? "<nil>"
        lines.append("--> \(method) \(urlStr)")

        if doBody {
            if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                for (k, v) in headers { lines.append("\(k): \(v)") }
            }

            if let body = request.httpBody, !body.isEmpty {
                if isProbablyUtf8(body) {
                    lines.append("")
                    lines.append(String(decoding: body, as: UTF8.self))
                } else {
                    lines.append("Request body is binary (omitted).")
                }
            }
        }

        lines.append("--> END \(method)")
        logger.log(level: lineLevel, className: "HTTP", message: lines.joined(separator: "\n"), cause: nil)
    }

    internal func logResponse(request: URLRequest, response: URLResponse?, data: Data?, error: (any Error)?, tookMs: Int) {
        guard isEnabled else { return }

        let lineLevel: LogLevel = doBody ? .verbose : .debug

        var lines: [String] = []

        if let error {
            lines.append("<-- HTTP FAILED: \(error)")
            logger.log(level: lineLevel, className: "HTTP", message: lines.joined(separator: "\n"), cause: error)
            return
        }

        let urlStr = request.url?.absoluteString ?? ""
        guard let http = response as? HTTPURLResponse else {
            lines.append("<-- (no HTTPURLResponse) \(urlStr) (\(tookMs)ms)")
            logger.log(level: lineLevel, className: "HTTP", message: lines.joined(separator: "\n"), cause: nil)
            return
        }

        lines.append("<-- \(http.statusCode) \(urlStr) (\(tookMs)ms)")

        if doBody {
            if !http.allHeaderFields.isEmpty {
                http.allHeaderFields.forEach { k, v in lines.append("\(k): \(v)") }
            }

            if let data, !data.isEmpty {
                if isProbablyUtf8(data) {
                    lines.append("")
                    lines.append(String(decoding: data, as: UTF8.self))
                } else {
                    lines.append("Response body is binary (omitted).")
                }
            }
        }

        lines.append("<-- END HTTP")
        logger.log(level: lineLevel, className: "HTTP", message: lines.joined(separator: "\n"), cause: nil)
    }

    private func isProbablyUtf8(_ data: Data) -> Bool {
        let prefix = data.prefix(64)
        if prefix.isEmpty { return true }
        if String(data: prefix, encoding: .utf8) == nil { return false }
        return !prefix.contains { b in b < 0x09 || (b > 0x0D && b < 0x20) }
    }
}
