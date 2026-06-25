import Foundation

internal struct InternalAttestationOptionsResponsePubKeyCredParamsItem: Sendable, Codable, Hashable {
    internal private(set) var type: InternalCredentialType
    internal private(set) var alg: InternalKeyAlgorithmType

    internal init(type: InternalCredentialType, alg: InternalKeyAlgorithmType) {
        self.type = type
        self.alg = alg
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case type = "type"
        case alg = "alg"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(alg, forKey: .alg)
    }
}
