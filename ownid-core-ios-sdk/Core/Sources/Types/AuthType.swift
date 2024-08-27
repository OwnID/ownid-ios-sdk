import Foundation

extension OwnID.CoreSDK {
    public enum AuthType: String, Codable {
        case biometrics
        case desktopBiometrics = "desktop-biometrics"
        case passkey
        case emailFallback = "email-fallback"
        case smsFallback = "sms-fallback"
        case otp
        case password
    }
}
