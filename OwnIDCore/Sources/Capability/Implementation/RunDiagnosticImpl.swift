import Foundation
import MetricKit

internal final class RunDiagnosticImpl: RunDiagnostic, @unchecked Sendable {
    internal typealias ExitProvider = @Sendable (_ processId: Int32) async -> PreviousRun.Exit?

    private struct RunRecord: Codable, Sendable {
        let correlationId: String
        let processId: Int32
    }

    private struct CrashCandidate: Sendable {
        let terminationReason: String?
        let signal: Int?
        let exceptionType: Int?
        let exceptionCode: String?

        var exit: PreviousRun.Exit {
            PreviousRun.Exit(
                diagnosticType: "crash",
                terminationReason: terminationReason,
                signal: signal,
                exceptionType: exceptionType,
                exceptionCode: exceptionCode
            )
        }
    }

    private static let storageSuiteName = "run_record"
    private static let storageKey = "RUN_RECORD"
    private static let diagnosticCollectionSeconds: TimeInterval = 5
    private static let diagnosticCollectionNanoseconds: UInt64 = 5_000_000_000

    private let lock = NSLock()
    private let storage: any Storage
    private let currentRun: RunRecord
    private let localLoggerProvider: @Sendable () -> (any OwnIDLogger)?
    private let exitProvider: ExitProvider
    private var isClaimed = false

    internal convenience init(
        localInfo: any LocalInfo,
        storageLogger: OwnIDLogRouter?,
        localLoggerProvider: @escaping @Sendable () -> (any OwnIDLogger)?
    ) {
        self.init(
            storage: StorageImpl(suiteName: Self.storageSuiteName, logger: storageLogger),
            correlationId: localInfo.correlationId,
            processId: ProcessInfo.processInfo.processIdentifier,
            localLoggerProvider: localLoggerProvider,
            exitProvider: RunDiagnosticImpl.collectCrashExit
        )
    }

    internal init(
        storage: any Storage,
        correlationId: String,
        processId: Int32,
        localLoggerProvider: @escaping @Sendable () -> (any OwnIDLogger)?,
        exitProvider: @escaping ExitProvider = RunDiagnosticImpl.collectCrashExit
    ) {
        self.storage = storage
        self.currentRun = RunRecord(correlationId: correlationId, processId: processId)
        self.localLoggerProvider = localLoggerProvider
        self.exitProvider = exitProvider
    }

    internal func reportPreviousRun(serverLogger: ServerLogger?) {
        let shouldStart = lock.withLock {
            guard !isClaimed else { return false }
            isClaimed = true
            return true
        }
        guard shouldStart else { return }

        Task.detached(priority: .utility) { [self, serverLogger] in
            await reportPreviousRunOnce(serverLogger: serverLogger)
        }
    }

    private func reportPreviousRunOnce(serverLogger: ServerLogger?) async {
        let previousRun = await readPreviousRun()

        do {
            let encodedCurrentRun = String(decoding: try JSONEncoder().encode(currentRun), as: UTF8.self)
            try await storage.putString(encodedCurrentRun, forKey: Self.storageKey)
        } catch {
            logLocally(message: "Failed to persist current run", cause: error)
            return
        }

        guard let previousRun, let serverLogger else { return }
        let exit = await exitProvider(previousRun.processId)
        serverLogger.log(
            level: .warn,
            className: "RunDiagnostic",
            message: "Previous run observed",
            cause: nil,
            previousRun: PreviousRun(
                correlationId: previousRun.correlationId,
                processId: previousRun.processId,
                exit: exit
            )
        )
    }

    private func readPreviousRun() async -> RunRecord? {
        guard let encoded = await storage.getString(forKey: Self.storageKey, defaultValue: nil) else { return nil }
        return try? JSONDecoder().decode(RunRecord.self, from: Data(encoded.utf8))
    }

    private static func collectCrashExit(for processId: Int32) async -> PreviousRun.Exit? {
        guard #available(iOS 17.0, *), Self.shouldUseLegacyMetricKit else { return nil }

        let collector = LegacyMetricKitCollector(
            processId: processId,
            deadlineUptime: ProcessInfo.processInfo.systemUptime + Self.diagnosticCollectionSeconds
        )
        MXMetricManager.shared.add(collector)
        try? await Task.sleep(nanoseconds: Self.diagnosticCollectionNanoseconds)
        let candidate = collector.finish()
        MXMetricManager.shared.remove(collector)
        return candidate?.exit
    }

    private func logLocally(message: String, cause: (any Error)?) {
        localLoggerProvider()?.log(level: .warn, className: "RunDiagnostic", message: message, cause: cause)
    }

    private static var shouldUseLegacyMetricKit: Bool {
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return majorVersion >= 17 && majorVersion < 27
    }

    // Callback state is protected by `lock`; MetricKit objects never leave `didReceive`.
    @available(iOS 17.0, *)
    private final class LegacyMetricKitCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
        private static let maximumTerminationReasonBytes = 512

        private let lock = NSLock()
        private let processId: Int32
        private let deadlineUptime: TimeInterval
        private var isFinished = false
        private var candidates: [CrashCandidate] = []

        fileprivate init(processId: Int32, deadlineUptime: TimeInterval) {
            self.processId = processId
            self.deadlineUptime = deadlineUptime
        }

        fileprivate func didReceive(_ payloads: [MXDiagnosticPayload]) {
            lock.withLock {
                guard !isFinished, ProcessInfo.processInfo.systemUptime <= deadlineUptime else { return }

                // Project Objective-C MetricKit objects into Sendable values within the callback.
                for diagnostic in payloads.flatMap({ $0.crashDiagnostics ?? [] })
                where diagnostic.metaData.pid == processId {
                    candidates.append(
                        CrashCandidate(
                            terminationReason: Self.truncateTerminationReason(diagnostic.terminationReason),
                            signal: diagnostic.signal?.intValue,
                            exceptionType: diagnostic.exceptionType?.intValue,
                            exceptionCode: diagnostic.exceptionCode.map { "0x" + String($0.uint64Value, radix: 16) }
                        )
                    )
                }
            }
        }

        fileprivate func finish() -> CrashCandidate? {
            lock.withLock {
                isFinished = true
                guard candidates.count == 1 else { return nil }
                return candidates[0]
            }
        }

        private static func truncateTerminationReason(_ value: String?) -> String? {
            guard let value else { return nil }
            guard value.utf8.count > maximumTerminationReasonBytes else { return value }

            var result = ""
            var byteCount = 0
            for character in value {
                let characterString = String(character)
                let characterByteCount = characterString.utf8.count
                guard byteCount + characterByteCount <= maximumTerminationReasonBytes else { break }
                result.append(character)
                byteCount += characterByteCount
            }
            return result
        }
    }
}
