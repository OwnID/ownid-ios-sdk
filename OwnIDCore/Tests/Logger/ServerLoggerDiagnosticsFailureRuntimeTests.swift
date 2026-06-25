import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@Suite(.serialized)
struct ServerLoggerDiagnosticsFailureRuntimeTests {

    @Test func `Serialization failure logs locally and skips diagnostics network`() async throws {
        let network = ScriptedDiagnosticsNetwork(responses: [.success(.init(url: Self.eventsURL, code: 202, headers: [:], body: "{}"))])
        let loggerSink = DiagnosticsLogSink()
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        defer { taskScope.shutdown() }

        let logger = try Self.makeLogger(
            network: network,
            coder: ThrowingDiagnosticsJSONCoder(),
            taskScope: taskScope,
            ownIdLogger: loggerSink
        )

        logger.log(level: .error, className: "Serializer", message: "cannot encode", cause: nil)

        let entry = try await loggerSink.waitForEntry("serialization failure log") { entry in
            entry.level == .warn
                && entry.className == "ServerLogger"
                && entry.message == "Failed to serialize log item"
                && entry.hasCause
        }

        #expect(entry.message == "Failed to serialize log item")
        #expect(await network.requests.isEmpty)
    }

    @Test func `Network failure is logged locally before retry timing`() async throws {
        let network = ScriptedDiagnosticsNetwork(
            responses: [
                .fail(.networkError(.init(url: Self.eventsURL, error: URLError(.cannotConnectToHost))))
            ]
        )
        let loggerSink = DiagnosticsLogSink()
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        defer { taskScope.shutdown() }

        let logger = try Self.makeLogger(
            network: network,
            coder: JSONCoderImpl(),
            taskScope: taskScope,
            ownIdLogger: loggerSink
        )

        logger.log(level: .error, className: "Transport", message: "cannot post", cause: nil)

        let entry = try await loggerSink.waitForEntry("network failure log") { entry in
            entry.level == .info
                && entry.className == "ServerLogger"
                && entry.message.contains("NetworkError")
                && entry.hasCause == false
        }
        taskScope.shutdown()

        #expect(entry.message.contains("NetworkError"))
        #expect(entry.message.contains("-1004"))
        #expect(await network.requestCount == 1)
    }

    @Test func `Network failures retry twice with deterministic timing and then stop`() async throws {
        let network = ScriptedDiagnosticsNetwork(
            responses: [
                Self.networkFailure(),
                Self.networkFailure(),
                Self.networkFailure(),
            ]
        )
        let loggerSink = DiagnosticsLogSink()
        let retrySleeper = ControlledDiagnosticsRetrySleeper()
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        defer { taskScope.shutdown() }

        let logger = try Self.makeLogger(
            network: network,
            coder: JSONCoderImpl(),
            taskScope: taskScope,
            ownIdLogger: loggerSink,
            retryDelayProvider: { UInt64($0 * 1_000) },
            retrySleeper: { try await retrySleeper.sleep(nanoseconds: $0) }
        )

        logger.log(level: .error, className: "Transport", message: "bounded retry", cause: nil)

        try await withTestTimeout("first diagnostics attempt") {
            await network.waitForRequestCount(1)
        }
        let firstDelay = try await withTestTimeout("first diagnostics retry delay") {
            await retrySleeper.waitForSleepCount(1)
        }
        #expect(firstDelay == [1_000])
        #expect(await network.requestCount == 1)

        await retrySleeper.resumeNext()

        try await withTestTimeout("second diagnostics attempt") {
            await network.waitForRequestCount(2)
        }
        let secondDelay = try await withTestTimeout("second diagnostics retry delay") {
            await retrySleeper.waitForSleepCount(2)
        }
        #expect(secondDelay == [1_000, 2_000])
        #expect(await network.requestCount == 2)

        await retrySleeper.resumeNext()

        try await withTestTimeout("third diagnostics attempt") {
            await network.waitForRequestCount(3)
        }
        _ = try await loggerSink.waitForEntryCount(3, "third diagnostics failure log") { entry in
            entry.level == .info
                && entry.className == "ServerLogger"
                && entry.message.contains("NetworkError")
        }

        #expect(await network.requestCount == 3)
        #expect(await retrySleeper.recordedDelays == [1_000, 2_000])
    }

    @Test func `Non-network diagnostics failures log once without retry scheduling`() async throws {
        let network = ScriptedDiagnosticsNetwork(
            responses: [
                .fail(.httpError(.init(url: Self.eventsURL, statusCode: 500, headers: [:], body: #"{"error":true}"#)))
            ]
        )
        let loggerSink = DiagnosticsLogSink()
        let retrySleeper = ControlledDiagnosticsRetrySleeper()
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        defer { taskScope.shutdown() }

        let logger = try Self.makeLogger(
            network: network,
            coder: JSONCoderImpl(),
            taskScope: taskScope,
            ownIdLogger: loggerSink,
            retryDelayProvider: { UInt64($0 * 1_000) },
            retrySleeper: { try await retrySleeper.sleep(nanoseconds: $0) }
        )

        logger.log(level: .error, className: "Transport", message: "http failure", cause: nil)

        let entry = try await loggerSink.waitForEntry("http failure log") { entry in
            entry.level == .info
                && entry.className == "ServerLogger"
                && entry.message.contains("HttpError(statusCode=500)")
        }

        #expect(entry.message == "HttpError(statusCode=500)")
        #expect(await network.requestCount == 1)
        #expect(await retrySleeper.recordedDelays.isEmpty)
    }

    private static let eventsURL = URL(string: "https://server-logger-diagnostics.ownid.test/events")!

    private static func networkFailure() -> NetworkResponse {
        .fail(.networkError(.init(url: Self.eventsURL, error: URLError(.cannotConnectToHost))))
    }

    private static func makeLogger(
        network: any NetworkProtocol,
        coder: any JSONCoder,
        taskScope: TaskScope,
        ownIdLogger: any OwnIDLogger,
        retryDelayProvider: @escaping ServerLogger.RetryDelayProvider = ServerLogger.defaultRetryDelayNanos(for:),
        retrySleeper: @escaping ServerLogger.RetrySleeper = { try await Task.sleep(nanoseconds: $0) }
    ) throws -> ServerLogger {
        let configuration = try OwnIDConfigurationImpl(
            appID: "DiagFailure123",
            env: .uat,
            region: .eu,
            rootURL: "https://server-logger-diagnostics.ownid.test"
        )
        return ServerLogger(
            instanceName: InstanceName(value: "ServerLoggerDiagnosticsFailureRuntimeTests-\(UUID().uuidString)"),
            configuration: configuration,
            localInfo: DiagnosticsServerLocalInfo(),
            appConfigProvider: ImmediateDiagnosticsAppConfigProvider(
                config: AppConfig(
                    loginIdConfig: AppConfig.default.loginIdConfig,
                    displayName: nil,
                    webView: nil,
                    ui: nil,
                    logLevel: .debug
                )
            ),
            network: network,
            coder: coder,
            taskScope: taskScope,
            ownIdLogger: ownIdLogger,
            retryDelayProvider: retryDelayProvider,
            retrySleeper: retrySleeper
        )
    }

}

private enum DiagnosticsFailureTestError: Error, Sendable {
    case encodingFailed
}

private actor ScriptedDiagnosticsNetwork: NetworkProtocol {
    private var responses: [NetworkResponse]
    private var recordedRequests: [NetworkRequest] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(responses: [NetworkResponse]) {
        self.responses = responses
    }

    var requests: [NetworkRequest] { recordedRequests }
    var requestCount: Int { recordedRequests.count }

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        recordedRequests.append(request)
        resumeRequestWaiters()
        if responses.isEmpty {
            return .success(.init(url: request.url, code: 202, headers: [:], body: "{}"))
        }
        return responses.removeFirst()
    }

    func waitForRequestCount(_ count: Int) async {
        if recordedRequests.count >= count { return }
        await withCheckedContinuation { continuation in
            if recordedRequests.count >= count {
                continuation.resume()
            } else {
                requestWaiters.append((count, continuation))
            }
        }
    }

    private func resumeRequestWaiters() {
        let completed = requestWaiters.filter { recordedRequests.count >= $0.count }.map(\.continuation)
        requestWaiters.removeAll { recordedRequests.count >= $0.count }
        completed.forEach { $0.resume() }
    }
}

private actor ControlledDiagnosticsRetrySleeper {
    private var delays: [UInt64] = []
    private var sleepWaiters: [(count: Int, continuation: CheckedContinuation<[UInt64], Never>)] = []
    private var sleepers: [CheckedContinuation<Void, any Error>] = []

    var recordedDelays: [UInt64] { delays }

    func sleep(nanoseconds: UInt64) async throws {
        delays.append(nanoseconds)
        resumeSleepWaiters()
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append(continuation)
        }
    }

    func waitForSleepCount(_ count: Int) async -> [UInt64] {
        if delays.count >= count { return delays }
        return await withCheckedContinuation { continuation in
            if delays.count >= count {
                continuation.resume(returning: delays)
            } else {
                sleepWaiters.append((count, continuation))
            }
        }
    }

    func resumeNext() {
        guard !sleepers.isEmpty else { return }
        sleepers.removeFirst().resume()
    }

    private func resumeSleepWaiters() {
        let completed = sleepWaiters.filter { delays.count >= $0.count }.map(\.continuation)
        sleepWaiters.removeAll { delays.count >= $0.count }
        completed.forEach { $0.resume(returning: delays) }
    }
}

private final class ThrowingDiagnosticsJSONCoder: JSONCoder, @unchecked Sendable {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func encodeToString<T: Encodable>(_ value: T) throws -> String {
        throw DiagnosticsFailureTestError.encodingFailed
    }

    func decodeFromString<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        throw DiagnosticsFailureTestError.encodingFailed
    }

    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        throw DiagnosticsFailureTestError.encodingFailed
    }

    func decodeFromJSONValue<T: Decodable>(_ element: JSONValue, as type: T.Type) throws -> T {
        throw DiagnosticsFailureTestError.encodingFailed
    }
}

private final class ImmediateDiagnosticsAppConfigProvider: AppConfigProvider, @unchecked Sendable {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            continuation.yield(config)
        }
    }

    func getOrFetchConfig() async throws -> AppConfig {
        config
    }
}

private struct DiagnosticsServerLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [("OwnIDCore", "0.0.0")]
    let bundleID = "com.ownid.diagnostics.failure.tests"
    let appVersion = "1.2.3"
    let userAgent = "OwnIDDiagnosticsFailureTests/1.2.3"
    let correlationId = "diagnostics-failure-correlation-id"
    let isDebuggable = true
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = true
    let isStrongBiometricEnabled = true
}

private final class DiagnosticsLogSink: OwnIDLogger, @unchecked Sendable {
    let level: LogLevel = .verbose
    let category = "OwnID-Diagnostics-Test"

    private let recorder = AsyncSignalRecorder<DiagnosticsLogEntry>()

    func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
        guard isEnabled(level) else { return }
        recorder.append(DiagnosticsLogEntry(level: level, className: className, message: message, hasCause: cause != nil))
    }

    func waitForEntry(
        _ timeoutDescription: String,
        seconds: UInt64 = 5,
        where predicate: @escaping @Sendable (DiagnosticsLogEntry) -> Bool
    ) async throws -> DiagnosticsLogEntry {
        try await recorder.waitForFirst(timeoutDescription, seconds: seconds, where: predicate)
    }

    func waitForEntryCount(
        _ count: Int,
        _ timeoutDescription: String,
        seconds: UInt64 = 5,
        where predicate: @escaping @Sendable (DiagnosticsLogEntry) -> Bool
    ) async throws -> [DiagnosticsLogEntry] {
        try await recorder.waitForCount(count, timeoutDescription, seconds: seconds, where: predicate)
    }
}

private struct DiagnosticsLogEntry: Sendable {
    let level: LogLevel
    let className: String
    let message: String
    let hasCause: Bool
}
