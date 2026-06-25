import Foundation

/// A token value that can represent authentication or single-operation proof.
///
/// The value is exactly one of ``AccessToken`` or ``ProofToken``. SDK surfaces use this wrapper when either token kind
/// can be produced by the same interaction. This wrapper has no public coding contract.
public enum AccessOrProofToken: Sendable, Equatable, Hashable {
    case accessToken(AccessToken)
    case proofToken(ProofToken)
}

/// A signed JWT that proves successful authentication.
///
/// The raw token is app-owned sensitive data. The SDK forwards it to OwnID APIs or app callbacks that explicitly accept
/// an access token; it does not make this model durable storage.
///
/// This model is publicly `Codable` with the ``token`` property. ``description`` returns a shortened value for
/// diagnostics and must not be used when the full token is required.
public struct AccessToken: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public let token: String

    public init(token: String) {
        self.token = token
    }

    public var description: String {
        "AccessToken(token: \(token.shorten()))"
    }

    internal func loginID(coder: any JSONCoder, validator: any LoginIDValidator) throws(TokenError) -> LoginID {
        guard let payload = decodeJwtPayload(token) else {
            throw TokenError(errorCode: .invalidArgument, message: "Invalid JWT payload")
        }

        let subject: String? = {
            guard let json = try? coder.decodeFromString(payload, as: JSONValue.self) else { return nil }
            return json["sub"]?.stringValue
        }()

        guard let subject, subject.isEmpty == false else {
            throw TokenError(errorCode: .invalidArgument, message: "JWT subject is missing")
        }

        return try parseLoginIdFromUrn(subject, validator: validator)
    }

    private func decodeJwtPayload(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadPart = String(parts[1])
        guard let data = payloadPart.decodeBase64UrlSafe() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func parseLoginIdFromUrn(_ urn: String, validator: any LoginIDValidator) throws(TokenError) -> LoginID {
        let parts = urn.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let explicitType: LoginIDType? = {
            guard parts.count == 2 else { return nil }
            let raw = String(parts[0])
            return LoginIDType.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }
        }()

        let id = explicitType != nil ? String(parts[1]) : urn
        if id.isEmpty {
            throw TokenError(errorCode: .invalidArgument, message: "Invalid loginID")
        }

        let type: LoginIDType
        if let explicitType {
            type = explicitType
        } else {
            do {
                type = try validator.determineLoginIDType(loginID: id)
            } catch {
                throw TokenError(errorCode: error.errorCode, message: error.message, underlyingError: error)
            }
        }

        do {
            return try validator.validate(LoginID(id: id, type: type))
        } catch {
            throw TokenError(errorCode: error.errorCode, message: error.message, underlyingError: error)
        }
    }
}

internal struct TokenError: Error, Sendable {
    internal let errorCode: ErrorCode
    internal let message: String
    internal let underlyingError: (any Error & Sendable)?

    internal init(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil) {
        self.errorCode = errorCode
        self.message = message
        self.underlyingError = underlyingError
    }
}

/// A signed JWT that proves a single successful operation.
///
/// A proof token is not a full app session token. Pass it only to SDK APIs or backend endpoints that explicitly expect
/// operation proof.
///
/// The raw token is app-owned sensitive data. This model is publicly `Codable` with the ``token`` property.
/// ``description`` returns a shortened value for diagnostics and must not be used when the full token is required.
public struct ProofToken: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public let token: String

    public init(token: String) {
        self.token = token
    }

    public var description: String {
        "ProofToken(token: \(token.shorten()))"
    }
}
