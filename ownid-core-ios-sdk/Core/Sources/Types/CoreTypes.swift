import Foundation
import SwiftUI

public extension OwnID.CoreSDK {
    /// Describes translations to be used in SDK. Languages chosen by order of initialization.
    struct Languages: RawRepresentable {
        public init(rawValue: [String]) {
            self.rawValue = rawValue
        }
        
        /// Tells SDK to change language if system language changes
        var shouldChangeLanguageOnSystemLanguageChange = true
        
        public let rawValue: [String]
    }
}

public extension OwnID.CoreSDK {
    struct Fido2LoginPayload: Encodable {
        var credentialId: String
        var clientDataJSON: String
        var authenticatorData: String
        var signature: String
        let error: String? = nil
    }
    
    struct Fido2RegisterPayload: Encodable {
        var credentialId: String
        var clientDataJSON: String
        var attestationObject: String
    }
}

public extension OwnID.CoreSDK {
    enum RequestType: String, Codable {
        case register
        case login
    }
    
    enum StatusResponseType: String, CaseIterable {
        case registrationInfo
        case session
    }
    
    enum LoginType: String, Codable {
        case standard
        case linkSocialAccount
    }
}

public protocol StringToken {
    var rawValue: String { get }
}

public protocol RegisterParameters { }

public extension OwnID.CoreSDK {
    
    struct ServerError {
        public let error: String
    }
    
    struct Payload {
        /// Used for later processing and creating login\registration requests
        public let data: String?
        public let metadata: Any?
        public let context: OwnID.CoreSDK.Context
        public let loginId: LoginID?
        public let responseType: StatusResponseType
        public let authType: AuthType?
        public let requestLanguage: String?
    }
}

public extension OwnID.CoreSDK {    
    struct LoginId {
        private enum Constants {
            static let defaultRegex = ".*"
        }
        
        let value: String
        let settings: LoginIdSettings
        
        init(value: String, settings: LoginIdSettings) {
            self.value = value
            self.settings = settings
        }
        
        var isValid: Bool {
            return NSPredicate(format:"SELF MATCHES %@", settings.regex ?? Constants.defaultRegex).evaluate(with: value)
        }
    }
}
