import Foundation
import CryptoKit

extension OwnID.CoreSDK {
    enum AuthMethod: String, Codable {
        case passkey
        case otp
        case password
        
        static func authMethod(from authType: OwnID.CoreSDK.AuthType?) -> AuthMethod? {
            guard let authType else {
                return nil
            }
            
            switch authType {
            case .biometrics, .desktopBiometrics, .passkey:
                return .passkey
            case .emailFallback, .smsFallback, .otp:
                return .otp
            case .password:
                return .password
            }
        }
    }
    
    final class LoginIdSaver {
        static func save(loginId: String, authMethod: AuthMethod? = nil) {
            DefaultsLoginIdSaver.save(loginId: loginId)
            LoginIdDataSaver.save(loginId: loginId, authMethod: authMethod)
        }
    }
    
    final class DefaultsLoginIdSaver {
        private static let loginIdKey = "login_id_saver_key"
        static func save(loginId: String) { UserDefaults.standard.set(loginId, forKey: loginIdKey) }
        
        static func loginId() -> String? { UserDefaults.standard.value(forKey: loginIdKey) as? String }
    }
    
    struct LoginIdData: Codable {
        var hashedLoginId: String
        var authMethod: AuthMethod?
        var lastEnrollmentTimeInterval: TimeInterval?
    }
    
    final class LoginIdDataSaver {
        private static let loginIdDataKey = "logid_id_data_saver_key"
        
        static func save(loginId: String,
                         authMethod: AuthMethod? = nil,
                         lastEnrollmentTimeInterval: TimeInterval? = nil) {
            var loginDataArray = loginIdDataArray()
            if let index = loginDataArray.firstIndex(where: { $0.hashedLoginId == hashedLoginId(loginId) }) {
                if let authMethod {
                    loginDataArray[index].authMethod = authMethod
                }
                if let lastEnrollmentTimeInterval {
                    loginDataArray[index].lastEnrollmentTimeInterval = lastEnrollmentTimeInterval
                }
                
                saveToArray(loginDataArray: loginDataArray)
            } else {
                var loginIdData = LoginIdData(hashedLoginId: hashedLoginId(loginId))
                if let authMethod {
                    loginIdData.authMethod = authMethod
                }
                if let lastEnrollmentTimeInterval {
                    loginIdData.lastEnrollmentTimeInterval = lastEnrollmentTimeInterval
                }
                loginDataArray.append(loginIdData)
                
                saveToArray(loginDataArray: loginDataArray)
            }
        }
        
        static func loginIdData(from loginId: String) -> LoginIdData? {
            return loginIdDataArray().first(where: { $0.hashedLoginId == hashedLoginId(loginId) })
        }
        
        private static func hashedLoginId(_ loginId: String) -> String {
            return SHA256.hash(data: Data((loginId).utf8)).data.toBase64URL()
        }
        
        private static func saveToArray(loginDataArray: [LoginIdData]) {
            do {
                let jsonData = try JSONEncoder().encode(loginDataArray)
                if let jsonStringArray = String(data: jsonData, encoding: .utf8) {
                    UserDefaults.standard.set(jsonStringArray, forKey: loginIdDataKey)
                }
            } catch {
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: error.localizedDescription))
                OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self).log()
            }
        }
        
        private static func loginIdDataArray() -> [LoginIdData] {
            let loginIdDataString = UserDefaults.standard.string(forKey: loginIdDataKey) ?? ""
            guard let jsonData = loginIdDataString.data(using: .utf8) else {
                return []
            }
            
            let loginDataArray = try? JSONDecoder().decode([LoginIdData].self, from: jsonData)
            return loginDataArray ?? []
        }
    }
}
