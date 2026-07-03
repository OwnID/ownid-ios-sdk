import Foundation

/// Resolves and validates login IDs according to the current OwnID application configuration.
///
/// Use ``determineLoginIDType(loginID:)`` when your app has a raw login ID string and needs the SDK to choose the first
/// supported ``LoginIDType`` whose classification rule matches that value.
///
/// Use ``validate(_:)`` when your app already has a typed ``LoginID`` and needs to check that the type is supported and
/// the value is valid for that type.
///
/// Login ID values are user identifiers. Validation failures may carry the rejected value for diagnostics, so avoid
/// forwarding failure descriptions to logs or analytics unless your app already treats that data as sensitive.
public protocol LoginIDValidator: Capability, Sendable {
    /// Determines the ``LoginIDType`` for the given raw `loginID` string.
    ///
    /// The resolved type is limited to the login-ID types supported by the current OwnID application configuration. The
    /// configured type order defines the match priority.
    ///
    /// - Returns: The supported ``LoginIDType`` resolved for `loginID`.
    /// - Throws: ``LoginIDValidationError/typeNotSupported(errorCode:message:)`` when the SDK cannot resolve `loginID`
    ///   to any supported type.
    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType
    /// Validates a typed ``LoginID``.
    ///
    /// Use this when your app already knows the login-ID type. Validation uses the configured regex for the declared
    /// type when present, or that type's default classification rule otherwise.
    ///
    /// - Returns: The validated ``LoginID``.
    /// - Throws: ``LoginIDValidationError/typeNotSupported(errorCode:message:)`` when `loginID` has a type that is not
    ///   supported by the current OwnID application configuration.
    /// - Throws: ``LoginIDValidationError/validationFailed(errorCode:message:loginID:regex:)`` when `loginID` is
    ///   supported but its value is invalid for the declared type.
    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID
}

/// Login ID classification or validation failure.
///
/// ``validationFailed(errorCode:message:loginID:regex:)`` includes the rejected ``LoginID`` and regex. Treat this
/// payload as sensitive diagnostic data.
public enum LoginIDValidationError: Error, Sendable, CustomStringConvertible {
    /// The login ID type is not supported by the current OwnID application configuration.
    ///
    /// This failure carries only ``errorCode`` and ``message``.
    case typeNotSupported(errorCode: ErrorCode, message: String)
    /// The login ID value does not match validation rules for its type.
    case validationFailed(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String)

    /// Localization key for resolving failure text.
    public var errorCode: ErrorCode {
        switch self {
        case .typeNotSupported(let errorCode, _): return errorCode
        case .validationFailed(let errorCode, _, _, _): return errorCode
        }
    }

    /// Diagnostic message associated with the failure.
    public var message: String {
        switch self {
        case .typeNotSupported(_, let message): return message
        case .validationFailed(_, let message, _, _): return message
        }
    }

    public var description: String {
        switch self {
        case .typeNotSupported:
            return "LoginIDValidationError.TypeNotSupported(errorCode=\(errorCode), message=\(message))"
        case .validationFailed(_, _, let loginID, let regex):
            return "LoginIDValidationError.ValidationFailed(errorCode=\(errorCode), message=\(message), loginID=\(loginID), regex=\(regex))"
        }
    }
}

/// Resolves a raw `loginID` into a typed ``LoginID`` by inferring its ``LoginIDType``.
///
/// This helper delegates to ``LoginIDValidator/determineLoginIDType(loginID:)`` and, on success, returns a new
/// ``LoginID`` that preserves the original raw value and appends the inferred type.
///
/// ``LoginIDValidationError`` from ``LoginIDValidator/determineLoginIDType(loginID:)`` is propagated unchanged.
extension LoginIDValidator {
    internal func appendWithType(_ loginID: String) throws(LoginIDValidationError) -> LoginID {
        LoginID(id: loginID, type: try determineLoginIDType(loginID: loginID))
    }
}
