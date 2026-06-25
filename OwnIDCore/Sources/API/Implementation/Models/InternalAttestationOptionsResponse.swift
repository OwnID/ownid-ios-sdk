import Foundation

internal struct InternalAttestationOptionsResponse: Sendable, Codable, Hashable {
    internal private(set) var rp: InternalRelayingParty
    internal private(set) var user: InternalFido2User
    internal private(set) var challenge: InternalChallengeId
    internal private(set) var pubKeyCredParams: [InternalAttestationOptionsResponsePubKeyCredParamsItem]
    internal private(set) var attestation: InternalAttestationConveyancePreference?
    internal private(set) var authenticatorSelection: InternalAttestationOptionsResponseAuthenticatorSelection?
    internal private(set) var timeout: InternalTimeout?
    internal private(set) var excludeCredentials: [InternalPublicKeyCredentialDescriptor]?

    internal init(
        rp: InternalRelayingParty,
        user: InternalFido2User,
        challenge: InternalChallengeId,
        pubKeyCredParams: [InternalAttestationOptionsResponsePubKeyCredParamsItem],
        attestation: InternalAttestationConveyancePreference? = nil,
        authenticatorSelection: InternalAttestationOptionsResponseAuthenticatorSelection? = nil,
        timeout: InternalTimeout? = nil,
        excludeCredentials: [InternalPublicKeyCredentialDescriptor]? = nil
    ) {
        self.rp = rp
        self.user = user
        self.challenge = challenge
        self.pubKeyCredParams = pubKeyCredParams
        self.attestation = attestation
        self.authenticatorSelection = authenticatorSelection
        self.timeout = timeout
        self.excludeCredentials = excludeCredentials
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case rp = "rp"
        case user = "user"
        case challenge = "challenge"
        case pubKeyCredParams = "pubKeyCredParams"
        case attestation = "attestation"
        case authenticatorSelection = "authenticatorSelection"
        case timeout = "timeout"
        case excludeCredentials = "excludeCredentials"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rp, forKey: .rp)
        try container.encode(user, forKey: .user)
        try container.encode(challenge, forKey: .challenge)
        try container.encode(pubKeyCredParams, forKey: .pubKeyCredParams)
        try container.encodeIfPresent(attestation, forKey: .attestation)
        try container.encodeIfPresent(authenticatorSelection, forKey: .authenticatorSelection)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(excludeCredentials, forKey: .excludeCredentials)
    }
}
