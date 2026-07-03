import Foundation

/// Configuration-backed ``LoginIDValidator``.
///
/// This implementation reads the current login-ID configuration on each call, so callers observe server configuration
/// changes after they are applied by the app-config provider. Raw values are matched in configured type order, and
/// typed values must be supported before their validation rule is evaluated.
internal final class LoginIDValidatorImpl: LoginIDValidator {
    private let loginIDConfigurationProvider: any LoginIDConfigurationProvider

    init(loginIDConfigurationProvider: any LoginIDConfigurationProvider) {
        self.loginIDConfigurationProvider = loginIDConfigurationProvider
    }

    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        let config = loginIDConfigurationProvider.configuration

        for type in config.supportedTypes {
            if isFullMatch(regex: type.classificationRegex, in: loginID) {
                return type
            }
        }

        throw LoginIDValidationError.typeNotSupported(
            errorCode: .loginIDTypeNotSupported,
            message: "LoginIDValidator.determineLoginIDType: Login ID type not supported"
        )
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        let configuration = loginIDConfigurationProvider.configuration
        guard configuration.supportedTypes.contains(loginID.type) else {
            throw LoginIDValidationError.typeNotSupported(
                errorCode: .loginIDTypeNotSupported,
                message: "LoginIDValidator.validate: Login ID type not supported"
            )
        }

        let validationRegex = (configuration.validationRegexes[loginID.type] ?? nil) ?? loginID.type.classificationRegex
        guard isFullMatch(regex: validationRegex, in: loginID.id) else {
            throw LoginIDValidationError.validationFailed(
                errorCode: .loginIDValidationFailed,
                message: "LoginIDValidator.validate: Login ID validation failed: \(loginID)",
                loginID: loginID,
                regex: validationRegex.pattern
            )
        }

        return loginID
    }

    private func isFullMatch(regex: NSRegularExpression, in value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return false }
        return match.range.location == range.location && match.range.length == range.length
    }
}
