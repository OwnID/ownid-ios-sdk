import Foundation

internal enum InternalTransportType: String, Sendable, Codable, Hashable, CaseIterable {
    case usb = "usb"
    case nfc = "nfc"
    case ble = "ble"
    case hybrid = "hybrid"
    case `internal` = "internal"
}
