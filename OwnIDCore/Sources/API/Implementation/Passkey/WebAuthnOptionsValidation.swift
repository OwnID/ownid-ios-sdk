import Foundation

internal enum WebAuthnOptionsValidation {
    private static let maxUserHandleBytes = 64
    private static let maxCredentialIDBytes = 1023

    internal static func validateAttestationOptionsResponse(_ response: InternalAttestationOptionsResponse) throws {
        _ = try decodeBase64URL(response.challenge.value, fieldPath: "attestation.challenge")
        let userID = try decodeBase64URL(response.user.id, fieldPath: "attestation.user.id")
        try validateSize(userID.count, fieldPath: "attestation.user.id", min: 1, max: maxUserHandleBytes)

        try response.excludeCredentials?.enumerated().forEach { index, credential in
            let credentialID = try decodeBase64URL(credential.id, fieldPath: "attestation.excludeCredentials[\(index)].id")
            try validateSize(
                credentialID.count,
                fieldPath: "attestation.excludeCredentials[\(index)].id",
                min: 0,
                max: maxCredentialIDBytes
            )
        }
    }

    internal static func validateAssertionOptionsResponse(_ response: InternalAssertionOptionsResponse) throws {
        _ = try decodeBase64URL(response.challenge.value, fieldPath: "assertion.challenge")

        try response.allowCredentials?.enumerated().forEach { index, credential in
            let credentialID = try decodeBase64URL(credential.id, fieldPath: "assertion.allowCredentials[\(index)].id")
            try validateSize(credentialID.count, fieldPath: "assertion.allowCredentials[\(index)].id", min: 0, max: maxCredentialIDBytes)
        }
    }

    private static func decodeBase64URL(_ value: String, fieldPath: String) throws -> Data {
        let normalizedValue = try normalizeBase64URL(value, fieldPath: fieldPath)
        guard let decoded = value.decodeBase64UrlSafe() else {
            throw WebAuthnOptionsValidationError(fieldPath: fieldPath, reason: "failed to decode base64url")
        }
        guard decoded.encodeToBase64UrlSafe() == normalizedValue else {
            throw WebAuthnOptionsValidationError(fieldPath: fieldPath, reason: "is not canonical base64url")
        }
        return decoded
    }

    private static func normalizeBase64URL(_ value: String, fieldPath: String) throws -> String {
        let unpadded: Substring
        if let paddingStart = value.firstIndex(of: "=") {
            let padding = value[paddingStart...]
            guard padding.count <= 2, padding.allSatisfy({ $0 == "=" }) else {
                throw WebAuthnOptionsValidationError(fieldPath: fieldPath, reason: "has invalid base64url padding")
            }
            guard value.count % 4 == 0 else {
                throw WebAuthnOptionsValidationError(fieldPath: fieldPath, reason: "has invalid base64url padding")
            }
            unpadded = value[..<paddingStart]
        } else {
            unpadded = value[...]
        }

        guard unpadded.count % 4 != 1 else {
            throw WebAuthnOptionsValidationError(fieldPath: fieldPath, reason: "has invalid base64url length")
        }
        guard unpadded.unicodeScalars.allSatisfy(isBase64URLScalar(_:)) else {
            throw WebAuthnOptionsValidationError(fieldPath: fieldPath, reason: "must be base64url")
        }
        return String(unpadded)
    }

    private static func validateSize(_ size: Int, fieldPath: String, min: Int, max: Int) throws {
        guard size >= min, size <= max else {
            throw WebAuthnOptionsValidationError(fieldPath: fieldPath, reason: "decoded size \(size) is outside \(min)...\(max) bytes")
        }
    }

    private static func isBase64URLScalar(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
            || (48...57).contains(scalar.value)
            || scalar.value == 45
            || scalar.value == 95
    }
}

internal struct WebAuthnOptionsValidationError: LocalizedError, Sendable, Equatable {
    internal let fieldPath: String
    internal let reason: String

    internal var errorDescription: String? {
        "Invalid WebAuthn options: \(fieldPath) \(reason)"
    }
}
