import Foundation

@_spi(OwnIDInternal) @testable import OwnIDCore

final class LogCapture: @unchecked Sendable {
    private let recorder = AsyncSignalRecorder<LogCaptureEntry>()

    var entries: [LogCaptureEntry] {
        recorder.entries
    }

    var messages: [String] {
        entries.map(\.message)
    }

    func append(level: LogLevel, className: String, message: String, hasCause: Bool, causeDescription: String? = nil) {
        recorder.append(
            LogCaptureEntry(
                level: level,
                className: className,
                message: message,
                hasCause: hasCause,
                causeDescription: causeDescription
            )
        )
    }

    func waitForEntry(
        containing fragment: String,
        timeoutDescription: String,
        seconds: UInt64 = 5
    ) async throws -> LogCaptureEntry {
        try await waitForEntry(timeoutDescription, seconds: seconds) {
            $0.message.contains(fragment) || $0.causeDescription?.contains(fragment) == true
        }
    }

    func waitForEntry(
        _ timeoutDescription: String,
        seconds: UInt64 = 5,
        where predicate: @escaping @Sendable (LogCaptureEntry) -> Bool
    ) async throws -> LogCaptureEntry {
        try await recorder.waitForFirst(timeoutDescription, seconds: seconds, where: predicate)
    }
}

struct LogCaptureEntry: Equatable, Sendable {
    let level: LogLevel
    let className: String
    let message: String
    let hasCause: Bool
    let causeDescription: String?
}

final class CapturingOwnIDLogger: OwnIDLogger, @unchecked Sendable {
    let level: LogLevel
    let category: String
    private let sink: LogCapture

    init(level: LogLevel = .verbose, category: String, sink: LogCapture) {
        self.level = level
        self.category = category
        self.sink = sink
    }

    func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
        guard isEnabled(level) else { return }
        sink.append(
            level: level,
            className: className,
            message: message,
            hasCause: cause != nil,
            causeDescription: cause?.localizedDescription
        )
    }
}

func testLogRouter(sink: LogCapture, category: String = "OwnID-Test") -> OwnIDLogRouter {
    let logger = CapturingOwnIDLogger(category: category, sink: sink)
    return OwnIDLogRouter(ownIDLoggerProvider: { logger }, serverLoggersProvider: { [] })
}
