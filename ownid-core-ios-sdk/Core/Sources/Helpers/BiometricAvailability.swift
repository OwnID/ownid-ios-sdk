import LocalAuthentication
import Foundation

extension OwnID.CoreSDK {
    static var isPasskeysSupported: Bool {
        let isLeastPasskeysSupportediOS = ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0))
        let isBiometricsAvailable = isTouchIDAvailable || isFaceIDAvailable
        let isPasskeysSupported = isLeastPasskeysSupportediOS && (isBiometricsAvailable || isPasscodeAvailable)
        return isPasskeysSupported
    }
    
    static var isPasscodeAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
    
    static var isTouchIDAvailable: Bool {
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            return context.biometryType == .touchID
        } else {
            return false
        }
    }
    
    static var isFaceIDAvailable: Bool {
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            return context.biometryType == .faceID
        } else {
            return false
        }
    }
}
