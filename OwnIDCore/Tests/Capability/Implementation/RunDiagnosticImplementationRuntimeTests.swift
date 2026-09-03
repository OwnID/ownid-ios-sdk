import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: DIAG-RUNTIME-060
@Suite(.serialized)
struct RunDiagnosticImplementationRuntimeTests {

    @Test func `Valid previous run rotates once and forwards one diagnostic`() async throws {
        let storage = RunDiagnosticStorage(
            strings: ["RUN_RECORD": #"{"correlationId":"previous-correlation","processId":321}"#]
        )
        let network = RunDiagnosticNetwork()
        let exitProcessIDs = AsyncSignalRecorder<Int32>()
        let harness = try Self.makeServerLogger(network: network)
        defer { harness.taskScope.shutdown() }
        let diagnostic = RunDiagnosticImpl(
            storage: storage,
            correlationId: "current-correlation",
            processId: 654,
            localLoggerProvider: { nil },
            exitProvider: { processID in
                exitProcessIDs.append(processID)
                return PreviousRun.Exit(
                    diagnosticType: "crash",
                    terminationReason: "synthetic forwarding fixture",
                    signal: 9,
                    exceptionType: 10,
                    exceptionCode: "0x2a"
                )
            }
        )

        diagnostic.reportPreviousRun(serverLogger: harness.logger)
        diagnostic.reportPreviousRun(serverLogger: harness.logger)

        let requests = try await network.waitForRequestCount(1)
        let request = try #require(requests.first)
        let payload = try Self.payload(from: request)
        let metadata = try #require(payload["metadata"] as? [String: Any])
        let previousRun = try #require(metadata["previousRun"] as? [String: Any])
        let exit = try #require(previousRun["exit"] as? [String: Any])
        let currentRun = try Self.jsonObject(from: try #require(storage.string(forKey: "RUN_RECORD")))

        #expect(storage.putAttempts == 1)
        #expect(exitProcessIDs.entries == [321])
        #expect(previousRun["correlationId"] as? String == "previous-correlation")
        #expect(previousRun["processId"] as? Int == 321)
        #expect(exit["diagnosticType"] as? String == "crash")
        #expect(exit["terminationReason"] as? String == "synthetic forwarding fixture")
        #expect(exit["signal"] as? Int == 9)
        #expect(exit["exceptionType"] as? Int == 10)
        #expect(exit["exceptionCode"] as? String == "0x2a")
        #expect(currentRun["correlationId"] as? String == "current-correlation")
        #expect(currentRun["processId"] as? Int == 654)
    }

    @Test func `First run persists current identity without publishing an event`() async throws {
        let storage = RunDiagnosticStorage()
        let network = RunDiagnosticNetwork()
        let harness = try Self.makeServerLogger(network: network)
        defer { harness.taskScope.shutdown() }
        let diagnostic = RunDiagnosticImpl(
            storage: storage,
            correlationId: "first-correlation",
            processId: 111,
            localLoggerProvider: { nil },
            exitProvider: { _ in
                Issue.record("Exit collection must not run without a previous record")
                return nil
            }
        )

        diagnostic.reportPreviousRun(serverLogger: harness.logger)
        try await storage.waitForPutCount(1)

        let currentRun = try Self.jsonObject(from: try #require(storage.string(forKey: "RUN_RECORD")))
        #expect(currentRun["correlationId"] as? String == "first-correlation")
        #expect(currentRun["processId"] as? Int == 111)
        #expect(network.requests.isEmpty)
    }

    @Test func `Nil first logger owns the one shot after rotation`() async throws {
        let storage = RunDiagnosticStorage(
            strings: ["RUN_RECORD": #"{"correlationId":"previous-correlation","processId":222}"#]
        )
        let network = RunDiagnosticNetwork()
        let harness = try Self.makeServerLogger(network: network)
        defer { harness.taskScope.shutdown() }
        let diagnostic = RunDiagnosticImpl(
            storage: storage,
            correlationId: "current-correlation",
            processId: 333,
            localLoggerProvider: { nil },
            exitProvider: { _ in
                Issue.record("Exit collection must not run without an owning server logger")
                return nil
            }
        )

        diagnostic.reportPreviousRun(serverLogger: nil)
        diagnostic.reportPreviousRun(serverLogger: harness.logger)
        try await storage.waitForPutCount(1)

        #expect(storage.putAttempts == 1)
        #expect(network.requests.isEmpty)
    }

    @Test func `Malformed previous record rotates without publishing a partial event`() async throws {
        let storage = RunDiagnosticStorage(strings: ["RUN_RECORD": "not-json"])
        let network = RunDiagnosticNetwork()
        let harness = try Self.makeServerLogger(network: network)
        defer { harness.taskScope.shutdown() }
        let diagnostic = RunDiagnosticImpl(
            storage: storage,
            correlationId: "replacement-correlation",
            processId: 444,
            localLoggerProvider: { nil },
            exitProvider: { _ in
                Issue.record("Exit collection must not run for a malformed record")
                return nil
            }
        )

        diagnostic.reportPreviousRun(serverLogger: harness.logger)
        try await storage.waitForPutCount(1)

        let currentRun = try Self.jsonObject(from: try #require(storage.string(forKey: "RUN_RECORD")))
        #expect(currentRun["correlationId"] as? String == "replacement-correlation")
        #expect(currentRun["processId"] as? Int == 444)
        #expect(network.requests.isEmpty)
    }

    @Test func `Persistence failure logs and publishes neither state nor event`() async throws {
        let storage = RunDiagnosticStorage(
            strings: ["RUN_RECORD": #"{"correlationId":"previous-correlation","processId":555}"#],
            putError: RunDiagnosticTestError.persistenceFailed
        )
        let network = RunDiagnosticNetwork()
        let logs = LogCapture()
        let localLogger = CapturingOwnIDLogger(category: "RunDiagnosticTests", sink: logs)
        let harness = try Self.makeServerLogger(network: network)
        defer { harness.taskScope.shutdown() }
        let diagnostic = RunDiagnosticImpl(
            storage: storage,
            correlationId: "uncommitted-correlation",
            processId: 666,
            localLoggerProvider: { localLogger },
            exitProvider: { _ in
                Issue.record("Exit collection must not run after persistence failure")
                return nil
            }
        )

        diagnostic.reportPreviousRun(serverLogger: harness.logger)
        _ = try await logs.waitForEntry(
            "current run persistence failure",
            where: { entry in
                entry.level == .warn
                    && entry.className == "RunDiagnostic"
                    && entry.message == "Failed to persist current run"
                    && entry.hasCause
            }
        )
        diagnostic.reportPreviousRun(serverLogger: harness.logger)

        #expect(storage.putAttempts == 1)
        #expect(storage.string(forKey: "RUN_RECORD")?.contains("previous-correlation") == true)
        #expect(network.requests.isEmpty)
    }

    private static func makeServerLogger(network: RunDiagnosticNetwork) throws -> RunDiagnosticServerLoggerHarness {
        let configuration = try OwnIDConfigurationImpl(
            appID: "RunDiagnostic123",
            env: .uat,
            region: .eu,
            rootURL: "https://run-diagnostic.ownid.test"
        )
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        let logger = ServerLogger(
            instanceName: InstanceName(value: "RunDiagnosticImplementationRuntimeTests-\(UUID().uuidString)"),
            configuration: configuration,
            localInfo: RunDiagnosticLocalInfo(),
            appConfigProvider: RunDiagnosticAppConfigProvider(),
            network: network,
            coder: JSONCoderImpl(),
            taskScope: taskScope
        )
        return RunDiagnosticServerLoggerHarness(logger: logger, taskScope: taskScope)
    }

    private static func payload(from request: NetworkRequest) throws -> [String: Any] {
        let data = try #require(request.buildURLRequest().httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private static func jsonObject(from string: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(string.utf8))
        return try #require(object as? [String: Any])
    }
}

private struct RunDiagnosticServerLoggerHarness {
    let logger: ServerLogger
    let taskScope: TaskScope
}

private final class RunDiagnosticNetwork: NetworkProtocol, @unchecked Sendable {
    private let recorder = AsyncSignalRecorder<NetworkRequest>()

    var requests: [NetworkRequest] { recorder.entries }

    func run(_ request: NetworkRequest) async throws -> NetworkResponse {
        recorder.append(request)
        return .success(.init(url: request.url, code: 202, headers: [:], body: "{}"))
    }

    func waitForRequestCount(_ count: Int) async throws -> [NetworkRequest] {
        try await recorder.waitForCount(count, "run diagnostic server request", where: { _ in true })
    }
}

private final class RunDiagnosticStorage: Storage, @unchecked Sendable {
    private let lock = NSLock()
    private let putRecorder = AsyncSignalRecorder<Int>()
    private let putError: (any Error)?
    private var strings: [String: String]
    private var bools: [String: Bool] = [:]
    private var numbers: [String: Int64] = [:]
    private var doubles: [String: Double] = [:]
    private var recordedPutAttempts = 0

    init(strings: [String: String] = [:], putError: (any Error)? = nil) {
        self.strings = strings
        self.putError = putError
    }

    var putAttempts: Int { lock.withLock { recordedPutAttempts } }

    func string(forKey key: String) -> String? {
        lock.withLock { strings[key] }
    }

    func waitForPutCount(_ count: Int) async throws {
        _ = try await putRecorder.waitForFirst("run record persistence") { $0 >= count }
    }

    func getString(forKey key: String, defaultValue: String?) async -> String? {
        lock.withLock { strings[key] ?? defaultValue }
    }

    func putString(_ value: String, forKey key: String) async throws {
        let attempt = lock.withLock {
            recordedPutAttempts += 1
            if putError == nil {
                strings[key] = value
            }
            return recordedPutAttempts
        }
        putRecorder.append(attempt)
        if let putError { throw putError }
    }

    func getBool(forKey key: String, defaultValue: Bool?) async -> Bool? {
        lock.withLock { bools[key] ?? defaultValue }
    }

    func putBool(_ value: Bool, forKey key: String) async throws {
        lock.withLock { bools[key] = value }
    }

    func getNumber(forKey key: String, defaultValue: Int64?) async -> Int64? {
        lock.withLock { numbers[key] ?? defaultValue }
    }

    func putNumber(_ value: Int64, forKey key: String) async throws {
        lock.withLock { numbers[key] = value }
    }

    func getDouble(forKey key: String, defaultValue: Double?) async -> Double? {
        lock.withLock { doubles[key] ?? defaultValue }
    }

    func putDouble(_ value: Double, forKey key: String) async throws {
        lock.withLock { doubles[key] = value }
    }

    func remove(forKey key: String) async throws {
        lock.withLock {
            strings[key] = nil
            bools[key] = nil
            numbers[key] = nil
            doubles[key] = nil
        }
    }
}

private struct RunDiagnosticAppConfigProvider: AppConfigProvider {
    private let config = AppConfig(
        loginIdConfig: AppConfig.default.loginIdConfig,
        displayName: nil,
        webView: nil,
        ui: nil,
        logLevel: .debug
    )

    var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            continuation.yield(config)
        }
    }

    func getOrFetchConfig() async throws -> AppConfig { config }
}

private struct RunDiagnosticLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [("OwnIDCore", "0.0.0")]
    let bundleID = "com.ownid.run-diagnostic.tests"
    let appVersion = "1.2.3"
    let userAgent = "OwnIDRunDiagnosticTests/1.2.3"
    let correlationId = "server-logger-correlation"
    let isDebuggable = true
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = true
}

private enum RunDiagnosticTestError: Error, Sendable {
    case persistenceFailed
}
