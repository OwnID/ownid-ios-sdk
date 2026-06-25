import Foundation

internal enum InternalLogLevel: String, Sendable, Codable, Hashable, CaseIterable {
    case error = "Error"
    case warning = "Warning"
    case information = "Information"
    case debug = "Debug"
    case none = "None"
}
