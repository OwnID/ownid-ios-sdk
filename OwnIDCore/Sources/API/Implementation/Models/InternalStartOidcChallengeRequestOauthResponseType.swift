import Foundation

/// The response type that will be used to resolve the challenge. Currently only a subset of the types in the protocol are supported
internal enum InternalStartOidcChallengeRequestOauthResponseType: String, Sendable, Codable, Hashable, CaseIterable {
    case code = "code"
    case idToken = "id_token"
}
