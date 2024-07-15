import Foundation

extension OwnID.CoreSDK {
    // MARK: - ServerConfiguration
    struct ServerConfiguration: Codable {
        var isFailed = false
        let supportedLocales: [String]?
        let logLevel: LogLevel?
        let passkeysAutofillEnabled: Bool?
        let serverURL: ServerURL
        let redirectURLString: RedirectionURLString?
        let platformSettings: PlatformSettings?
        let loginIdSettings: LoginIdSettings?
        let verification: Verification?
        let enableRegistrationFromLogin: Bool?
        let phoneCodes: [PhoneCode]?
        let origins: [String]?
        let displayName: String?
        let webViewSettings: WebViewSettings?

        enum CodingKeys: String, CodingKey {
            case supportedLocales, logLevel, passkeysAutofillEnabled, verification, enableRegistrationFromLogin, phoneCodes, displayName
            case loginIdSettings = "loginId"
            case serverURL = "serverUrl"
            case redirectURLString = "redirectUrl"
            case platformSettings = "iosSettings"
            case origins = "origin"
            case webViewSettings = "webview"
        }
    }
    
    // MARK: - PlatformSettings
    struct PlatformSettings: Codable {
        let redirectUrlOverride: RedirectionURLString?
        let bundleId: String?
    }
    
    //MARK: - Login Id
    struct LoginIdSettings: Codable {
        enum LoginIdType: String, Codable {
            case email, phoneNumber, userName
        }
        
        let type: LoginIdType
        let regex: String?
        
        init(type: LoginIdType, regex: String?) {
            self.type = type
            self.regex = regex
        }
    }
    
    //MARK: - Verification Type
    struct Verification: Codable {
        enum VerificationType: String, Codable {
            case email, sms
        }
        
        let type: VerificationType
        
        init(type: VerificationType) {
            self.type = type
        }
    }
    
    //MARK: - Phone Codes
    struct PhoneCode: Codable, Identifiable, Equatable {
        let code: String
        let dialCode: String
        let emoji: String
        let name: String
        
        var id: String { code }

        static func == (lhs: PhoneCode, rhs: PhoneCode) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    struct WebViewSettings: Codable {
        enum CodingKeys: String, CodingKey {
            case html
            case baseURL = "baseUrl"
        }
        
        let html: String
        let baseURL: String
    }
}

extension OwnID.CoreSDK.ServerConfiguration {
    static func mock(isFailed: Bool = false) -> Self {
        Self(isFailed: isFailed, supportedLocales: [], logLevel: .error, passkeysAutofillEnabled: false, serverURL: URL(string: "https://ownid.com")!, redirectURLString: nil, platformSettings: nil, loginIdSettings: OwnID.CoreSDK.LoginIdSettings(type: .email, regex: ""), verification: OwnID.CoreSDK.Verification(type: .email), enableRegistrationFromLogin: true, phoneCodes: [], origins: [], displayName: nil, webViewSettings: OwnID.CoreSDK.WebViewSettings(html: "", baseURL: ""))
    }
}
