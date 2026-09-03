import Foundation

internal struct PreviousRun: Encodable, Sendable {
    internal struct Exit: Encodable, Sendable {
        internal let diagnosticType: String
        internal let terminationReason: String?
        internal let signal: Int?
        internal let exceptionType: Int?
        internal let exceptionCode: String?
    }

    internal let correlationId: String
    internal let processId: Int32
    internal let exit: Exit?
}

/// Process-wide rotation and best-effort reporting of the previous SDK run.
internal protocol RunDiagnostic: Capability, Sendable {
    func reportPreviousRun(serverLogger: ServerLogger?)
}
