import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct LoggerBoundaryContractTests {

    @Test func `Custom logger sink replaces default local sink and applies configured threshold`() {
        let sink = LogSink()
        let cause = NSError(domain: "LoggerBoundaryContractTests", code: 7)

        let logger = OwnIDLoggerBuilder().apply {
            $0.level = .info
            $0.category = "OwnID-Test"
            $0.log { level, className, message, cause in
                sink.append(level: level, className: className, message: message, hasCause: cause != nil)
            }
        }.build()

        logger.log(level: .debug, className: "Source", message: "below threshold", cause: nil)
        logger.log(level: .info, className: "Source", message: "visible", cause: cause)

        #expect(logger.category == "OwnID-Test")
        #expect(logger.isEnabled(.debug) == false)
        #expect(logger.isEnabled(.info) == true)
        #expect(sink.entries == [LogEntry(level: .info, className: "Source", message: "visible", hasCause: true)])
    }

    @Test func `Log router fans out to current local logger and normalizes missing message`() throws {
        let sink = LogSink()
        let logger = CapturingLogger(level: .verbose, category: "OwnID-Test", sink: sink)
        let router = OwnIDLogRouter(ownIDLoggerProvider: { logger }, serverLoggersProvider: { [] })

        router.logW(source: self, prefix: "prefix", message: nil)

        let entry = try #require(sink.entries.first)
        #expect(sink.entries.count == 1)
        #expect(entry.level == .warn)
        #expect(entry.className.contains("LoggerBoundaryContractTests#"))
        #expect(entry.className.contains(":prefix"))
        #expect(entry.message == "")
    }

    @Test func `Network request suppress HTTP log flag is per request and does not change built request shape`() throws {
        let url = try #require(URL(string: "https://example.test/events"))
        let normal = NetworkRequest(url: url)
        var suppressed = NetworkRequest(url: url)
        suppressed.setSuppressHttpLog()

        let normalRequest = normal.buildURLRequest()
        let suppressedRequest = suppressed.buildURLRequest()

        #expect(normal.suppressHttpLog == false)
        #expect(suppressed.suppressHttpLog == true)
        #expect(normalRequest.url == suppressedRequest.url)
        #expect(normalRequest.httpMethod == suppressedRequest.httpMethod)
        #expect(normalRequest.httpBody == suppressedRequest.httpBody)
    }

    private final class CapturingLogger: OwnIDLogger, @unchecked Sendable {
        let level: LogLevel
        let category: String
        private let sink: LogSink

        init(level: LogLevel, category: String, sink: LogSink) {
            self.level = level
            self.category = category
            self.sink = sink
        }

        func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
            guard isEnabled(level) else { return }
            sink.append(level: level, className: className, message: message, hasCause: cause != nil)
        }
    }

    private final class LogSink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [LogEntry] = []

        var entries: [LogEntry] {
            lock.withLock { storage }
        }

        func append(level: LogLevel, className: String, message: String, hasCause: Bool) {
            lock.withLock {
                storage.append(LogEntry(level: level, className: className, message: message, hasCause: hasCause))
            }
        }
    }

    private struct LogEntry: Equatable, Sendable {
        let level: LogLevel
        let className: String
        let message: String
        let hasCause: Bool
    }
}
