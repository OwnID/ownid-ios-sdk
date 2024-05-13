import Foundation

extension OwnID.CoreSDK.EnrollManager {
    final class EnrollNotNowSaver {
        private static let enrollNotNowKey = "enroll_not_now_saver_key"
        static func save(loginId: String) {
            var dict = enrollNotNowDict() ?? [:]
            dict[loginId] = Date().timeIntervalSince1970
            
            UserDefaults.standard.set(dict, forKey: enrollNotNowKey)
        }
        
        static func enrollNotNowDict() -> [String: TimeInterval]? {
            UserDefaults.standard.value(forKey: enrollNotNowKey) as? [String: TimeInterval]
        }
    }
}
