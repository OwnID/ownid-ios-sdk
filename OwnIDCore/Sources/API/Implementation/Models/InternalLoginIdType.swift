import Foundation

internal enum InternalLoginIdType: String, Sendable, Codable, Hashable, CaseIterable {
    case anonymous = "Anonymous"
    case userName = "UserName"
    case email = "Email"
    case phoneNumber = "PhoneNumber"
    case credentialId = "CredentialId"
    case faceKeyPersonId = "FaceKeyPersonId"
}
