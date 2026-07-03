import Foundation

/// Creates and advances `traceparent` values for SDK network requests.
///
/// New contexts use version `00`, a non-zero 16-byte trace ID, a non-zero 8-byte parent ID, and trace flags `01`.
/// Existing values are accepted only when they contain four hexadecimal fields with lengths 2/32/16/2, a version other
/// than `ff`, and non-zero trace and parent IDs. Accepted values keep their version, trace ID, and trace flags while
/// rotating the parent ID for each outbound send attempt.
internal enum TraceContext {
    /// Parsed trace seed reused across retry attempts for one logical request.
    internal struct Seed {
        let version: String
        let traceID: String
        let traceFlags: String

        fileprivate init(version: String, traceID: String, traceFlags: String) {
            self.version = version
            self.traceID = traceID
            self.traceFlags = traceFlags
        }

        fileprivate init?(traceParent: String?) {
            guard let traceParent else { return nil }
            let parts = traceParent.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }

            let version = String(parts[0]).lowercased()
            let traceID = String(parts[1]).lowercased()
            let parentID = String(parts[2]).lowercased()
            let traceFlags = String(parts[3]).lowercased()

            guard
                version.isLowerHex(length: 2),
                traceID.isLowerHex(length: 32),
                parentID.isLowerHex(length: 16),
                traceFlags.isLowerHex(length: 2),
                version != "ff",
                !traceID.isAllZeroHex,
                !parentID.isAllZeroHex
            else { return nil }

            self.init(version: version, traceID: traceID, traceFlags: traceFlags)
        }

        fileprivate static func generated() -> Seed {
            Seed(
                version: "00",
                traceID: TraceContext.nonZeroRandomHex(bytes: 16),
                traceFlags: "01"
            )
        }
    }

    /// Generates a complete `traceparent` value for a new logical request.
    internal static func generateTraceParent() -> String {
        nextTraceParent(seed: .generated())
    }

    /// Returns a parsed seed from `traceParent`, or a new seed when the value is missing or invalid.
    internal static func resolveSeed(_ traceParent: String?) -> Seed {
        Seed(traceParent: traceParent) ?? .generated()
    }

    /// Builds the next `traceparent` value by preserving `seed` and generating a new parent ID.
    internal static func nextTraceParent(seed: Seed) -> String {
        let parentID = nonZeroRandomHex(bytes: 8)
        return "\(seed.version)-\(seed.traceID)-\(parentID)-\(seed.traceFlags)"
    }

    private static func nonZeroRandomHex(bytes: Int) -> String {
        while true {
            let data = Data.secureRandom(count: bytes)
            if data.contains(where: { $0 != 0 }) {
                return data.map { String(format: "%02x", $0) }.joined()
            }
        }
    }
}

extension String {
    fileprivate func isLowerHex(length: Int) -> Bool {
        count == length && allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    fileprivate var isAllZeroHex: Bool {
        allSatisfy { $0 == "0" }
    }
}
