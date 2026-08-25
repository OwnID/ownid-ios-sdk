import Foundation
import MetricKit

extension OwnID.CoreSDK {
    internal struct PreviousRun: Encodable {
        internal struct Exit: Encodable {
            let diagnosticType: String
            let terminationReason: String?
            let signal: Int?
            let exceptionType: Int?
            let exceptionCode: String?
        }

        let correlationId: String
        let processId: Int32
        let exit: Exit?
    }

    /// Rotates the process run record once and reports the previous run on a best-effort basis.
    internal final class RunDiagnostic {
        private struct RunRecord: Codable {
            let correlationId: String
            let processId: Int32
        }

        private struct CrashCandidate {
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

        private static let storageKey = "com.ownid.sdk.storage.RUN_RECORD"
        private static let diagnosticCollectionSeconds: TimeInterval = 5

        static let shared = RunDiagnostic()

        private let claimLock = NSLock()
        private let queue = DispatchQueue(label: "com.ownid.sdk.run-diagnostic", qos: .utility)
        // Initialized on `queue` so configuration never performs file I/O on its caller's thread.
        private lazy var storage = RunRecordStorage()
        private var isClaimed = false

        private init() {}

        func reportPreviousRun() {
            claimLock.lock()
            guard !isClaimed else {
                claimLock.unlock()
                return
            }
            isClaimed = true
            claimLock.unlock()

            queue.async { [self] in
                reportPreviousRunOnce()
            }
        }

        private func reportPreviousRunOnce() {
            let previousRun = readPreviousRun()
            let currentRun = RunRecord(
                correlationId: LoggerConstants.instanceID.uuidString,
                processId: ProcessInfo.processInfo.processIdentifier
            )

            do {
                let encodedCurrentRun = String(decoding: try JSONEncoder().encode(currentRun), as: UTF8.self)
                try storage.putString(encodedCurrentRun, forKey: Self.storageKey)
            } catch {
                OwnID.CoreSDK.logger.log(
                    level: .warning,
                    message: "Failed to persist current run",
                    errorMessage: error.localizedDescription,
                    type: RunDiagnostic.self
                )
                return
            }

            guard let previousRun else { return }
            collectCrashExit(for: previousRun.processId) { exit in
                let previousRun = PreviousRun(
                    correlationId: previousRun.correlationId,
                    processId: previousRun.processId,
                    exit: exit
                )
                OwnID.CoreSDK.eventService.sendMetric(.previousRunMetric(previousRun))
            }
        }

        private func readPreviousRun() -> RunRecord? {
            guard let encoded = storage.getString(forKey: Self.storageKey) else { return nil }
            return try? JSONDecoder().decode(RunRecord.self, from: Data(encoded.utf8))
        }

        private func collectCrashExit(
            for processId: Int32,
            completion: @escaping (PreviousRun.Exit?) -> Void
        ) {
            guard #available(iOS 17.0, *), Self.shouldUseLegacyMetricKit else {
                completion(nil)
                return
            }

            let collector = LegacyMetricKitCollector(
                processId: processId,
                deadlineUptime: ProcessInfo.processInfo.systemUptime + Self.diagnosticCollectionSeconds
            )
            MXMetricManager.shared.add(collector)
            queue.asyncAfter(deadline: .now() + Self.diagnosticCollectionSeconds) {
                let candidate = collector.finish()
                MXMetricManager.shared.remove(collector)
                completion(candidate?.exit)
            }
        }

        private static var shouldUseLegacyMetricKit: Bool {
            let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            return majorVersion >= 17 && majorVersion < 27
        }

        @available(iOS 17.0, *)
        private final class LegacyMetricKitCollector: NSObject, MXMetricManagerSubscriber {
            private static let maximumTerminationReasonBytes = 512

            private let lock = NSLock()
            private let processId: Int32
            private let deadlineUptime: TimeInterval
            private var isFinished = false
            private var candidates: [CrashCandidate] = []

            init(processId: Int32, deadlineUptime: TimeInterval) {
                self.processId = processId
                self.deadlineUptime = deadlineUptime
            }

            func didReceive(_ payloads: [MXDiagnosticPayload]) {
                lock.lock()
                defer { lock.unlock() }
                guard !isFinished, ProcessInfo.processInfo.systemUptime <= deadlineUptime else { return }

                for diagnostic in payloads.flatMap({ $0.crashDiagnostics ?? [] })
                where diagnostic.metaData.pid == processId {
                    candidates.append(
                        CrashCandidate(
                            terminationReason: Self.truncateTerminationReason(diagnostic.terminationReason),
                            signal: diagnostic.signal?.intValue,
                            exceptionType: diagnostic.exceptionType?.intValue,
                            exceptionCode: diagnostic.exceptionCode.map {
                                "0x" + String($0.uint64Value, radix: 16)
                            }
                        )
                    )
                }
            }

            func finish() -> CrashCandidate? {
                lock.lock()
                defer { lock.unlock() }
                isFinished = true
                guard candidates.count == 1 else { return nil }
                return candidates[0]
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

    /// Storage dedicated to the v4-compatible run record file.
    private final class RunRecordStorage {
        private struct StoredValue: Codable {
            var string: String?
            var bool: Bool?
            var number: Int64?
            var double: Double?
        }

        private let fileURL: URL
        private var store: [String: StoredValue]

        init() {
            let directoryURL: URL
            if let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first {
                directoryURL = applicationSupport.appendingPathComponent(
                    "com.ownid.sdk/storage",
                    isDirectory: true
                )
            } else {
                directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "com.ownid.sdk/storage",
                    isDirectory: true
                )
            }

            fileURL = directoryURL.appendingPathComponent("run_record.plist")
            store = Self.loadStore(from: fileURL)
        }

        func getString(forKey key: String) -> String? {
            store[key]?.string
        }

        func putString(_ value: String, forKey key: String) throws {
            var candidate = store
            candidate[key] = StoredValue(string: value)

            let data = try PropertyListEncoder().encode(candidate)
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            Self.excludeFromBackup(directoryURL)
            try data.write(to: fileURL, options: .atomic)
            Self.excludeFromBackup(fileURL)
            store = candidate
        }

        private static func loadStore(from fileURL: URL) -> [String: StoredValue] {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }

            do {
                let data = try Data(contentsOf: fileURL)
                return try PropertyListDecoder().decode([String: StoredValue].self, from: data)
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                return [:]
            }
        }

        private static func excludeFromBackup(_ url: URL) {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        }
    }
}
