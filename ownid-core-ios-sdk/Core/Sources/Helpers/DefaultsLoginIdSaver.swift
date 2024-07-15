import Foundation

extension OwnID.CoreSDK {
    final class DefaultsLoginIdSaver {
        private static let loginIdKey = "login_id_saver_key"
        static func save(loginId: String) { UserDefaults.standard.set(loginId, forKey: loginIdKey) }
        
        static func loginId() -> String? { UserDefaults.standard.value(forKey: loginIdKey) as? String }
    }
    
    struct LoginIdData: Codable {
        var loginId: String
        var isOwnIdLogin = false
        var lastEnrollmentTimeInterval: TimeInterval?
    }
    
    final class LoginIdDataSaver {
        private static let loginIdDataKey = "logid_id_data_saver_key"
        
        static func save(loginId: String,
                         isOwnIdLogin: Bool? = nil,
                         lastEnrollmentTimeInterval: TimeInterval? = nil) {
            var loginDataArray = loginIdDataArray()
            if let index = loginDataArray.firstIndex(where: { $0.loginId == loginId }) {
                if let isOwnIdLogin, isOwnIdLogin {
                    loginDataArray[index].isOwnIdLogin = isOwnIdLogin
                }
                if let lastEnrollmentTimeInterval {
                    loginDataArray[index].lastEnrollmentTimeInterval = lastEnrollmentTimeInterval
                }
                
                saveToArray(loginDataArray: loginDataArray)
            } else {
                var loginIdData = LoginIdData(loginId: loginId)
                if let isOwnIdLogin {
                    loginIdData.isOwnIdLogin = isOwnIdLogin
                }
                if let lastEnrollmentTimeInterval {
                    loginIdData.lastEnrollmentTimeInterval = lastEnrollmentTimeInterval
                }
                loginDataArray.append(loginIdData)
                
                saveToArray(loginDataArray: loginDataArray)
            }
        }
        
        static func loginIdData(from loginId: String) -> LoginIdData? {
            return loginIdDataArray().first(where: { $0.loginId == loginId })
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
