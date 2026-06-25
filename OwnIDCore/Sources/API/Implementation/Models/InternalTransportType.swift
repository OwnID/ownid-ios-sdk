import Foundation

internal enum InternalTransportType: String, Sendable, Codable, Hashable, CaseIterable {
    case usb = "usb"
    case nfc = "nfc"
    case ble = "ble"
    case smartCard = "smart-card"
    case hybrid = "hybrid"
    case `internal` = "internal"
    case cable = "cable"
}
