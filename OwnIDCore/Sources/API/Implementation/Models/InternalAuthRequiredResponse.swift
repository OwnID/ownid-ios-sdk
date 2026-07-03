import Foundation

internal struct InternalAuthRequiredResponse: Sendable, Codable, Hashable {
    /// The reason why the session was not created
    internal private(set) var reason: String?
    /// Hint if the account was not found. Will be provided in a discovery call only for apps that enable this exposure.
    internal private(set) var accountNotFound: Bool?
    /// Hint if the account is blocked. Will be provided in a discovery call only for apps that enable this exposure.
    internal private(set) var accountBlocked: Bool?
    /// Required operations needed to complete authentication.
    internal private(set) var authRequirements: InternalAuthRequirements?

    internal init(
        reason: String? = nil,
        accountNotFound: Bool? = nil,
        accountBlocked: Bool? = nil,
        authRequirements: InternalAuthRequirements? = nil
    ) {
        self.reason = reason
        self.accountNotFound = accountNotFound
        self.accountBlocked = accountBlocked
        self.authRequirements = authRequirements
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case reason = "reason"
        case accountNotFound = "accountNotFound"
        case accountBlocked = "accountBlocked"
        case authRequirements = "authRequirements"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.accountNotFound = try container.decodeIfPresent(Bool.self, forKey: .accountNotFound)
        self.accountBlocked = try container.decodeIfPresent(Bool.self, forKey: .accountBlocked)
        self.authRequirements = try container.decodeIfPresent(InternalAuthRequirements.self, forKey: .authRequirements)
        let selectedBranchesCount = (accountNotFound != nil ? 1 : 0) + (accountBlocked != nil ? 1 : 0) + (authRequirements != nil ? 1 : 0)
        guard selectedBranchesCount == 1 else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Exactly one of accountNotFound, accountBlocked, or authRequirements must be present."
                )
            )
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let selectedBranchesCount = (accountNotFound != nil ? 1 : 0) + (accountBlocked != nil ? 1 : 0) + (authRequirements != nil ? 1 : 0)
        guard selectedBranchesCount == 1 else {
            throw EncodingError.invalidValue(
                self,
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Exactly one of accountNotFound, accountBlocked, or authRequirements must be present."
                )
            )
        }
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(accountNotFound, forKey: .accountNotFound)
        try container.encodeIfPresent(accountBlocked, forKey: .accountBlocked)
        try container.encodeIfPresent(authRequirements, forKey: .authRequirements)
    }
}
