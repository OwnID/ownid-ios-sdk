import Foundation
import Gigya
import OwnIDCoreSDK
import Combine

extension OwnID.GigyaSDK {
    struct SessionInfo: Decodable {
        let sessionToken: String
        let sessionSecret: String
        let expires_in: String
        
        var expiration: Double {
            Double(expires_in) ?? 0
        }
    }
}

extension OwnID.GigyaSDK {
    public struct ErrorMetadata: Codable {
        public let callID: String?
        public let errorCode: Int?
        public let errorDetails, errorMessage: String?
        public let apiVersion, statusCode: Int?
        public let statusReason, time: String?
        public let registeredTimestamp: Int?
        public let uid, created: String?
        public let createdTimestamp: Int?
        public let identities: [Identity]?
        public let isActive, isRegistered, isVerified: Bool?
        public let lastLogin: String?
        public let lastLoginTimestamp: Int?
        public let lastUpdated: String?
        public let lastUpdatedTimestamp: Int?
        public let loginProvider, oldestDataUpdated: String?
        public let oldestDataUpdatedTimestamp: Int?
        public let profile: Profile?
        public let registered, socialProviders: String?
        public let newUser: Bool?
        public let idToken, regToken: String?

        enum CodingKeys: String, CodingKey {
            case callID = "callId"
            case errorCode, errorDetails, errorMessage, apiVersion, statusCode, statusReason, time, registeredTimestamp
            case uid = "UID"
            case created, createdTimestamp, identities, isActive, isRegistered, isVerified, lastLogin, lastLoginTimestamp, lastUpdated, lastUpdatedTimestamp, loginProvider, oldestDataUpdated, oldestDataUpdatedTimestamp, profile, registered, socialProviders, newUser
            case idToken = "id_token"
            case regToken
        }
    }
    
    public struct Identity: Codable {
        public let provider, providerUID: String?
        public let allowsLogin, isLoginIdentity, isExpiredSession: Bool?
        public let lastUpdated: String?
        public let lastUpdatedTimestamp: Int?
        public let oldestDataUpdated: String?
        public let oldestDataUpdatedTimestamp: Int?
        public let firstName, nickname, email: String?
    }
    
    public struct Profile: Codable {
        public let firstName, email: String?
    }
}

extension OwnID.GigyaSDK {
    private enum Constants {
        static let errorKey = "errorJson"
        static let sessionInfoKey = "sessionInfo"
    }
    
    enum LogIn {
        static func logIn<T: GigyaAccountProtocol>(instance: GigyaCore<T>, payload: OwnID.CoreSDK.Payload) -> EventPublisher {
            Future<OwnID.LoginResult, OwnID.CoreSDK.Error> { promise in
                func handle(error: OwnID.CoreSDK.Error, customErrorMessage: String? = nil) {
                    OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self).log(customErrorMessage: customErrorMessage)
                    promise(.failure(error))
                }
                
                let data = Data((payload.data ?? "").utf8)
                guard let dataJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    handle(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: ErrorMessage.cannotParseSession)))
                    return
                }
                
                if let errorString = dataJson[Constants.errorKey] as? String,
                   let errorData = errorString.data(using: .utf8),
                   let errorMetadata = try? JSONDecoder().decode(GigyaResponseModel.self, from: errorData) {
                    ErrorMapper<T>.mapLoginError(errorCode: errorMetadata.errorCode,
                                                 context: payload.context,
                                                 loginId: payload.loginId,
                                                 authType: payload.authType)
                    let gigyaError = NetworkError.gigyaError(data: errorMetadata)
                    let json = try? JSONSerialization.jsonObject(with: errorData, options: []) as? [String: Any]
                    let error = IntegrationError.gigyaSDKError(gigyaError: gigyaError, dataDictionary: json)
                    handle(error: .integrationError(underlying: error))
                    return
                }
                guard let sessionData = dataJson[Constants.sessionInfoKey] as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: sessionData),
                      let sessionInfo = try? JSONDecoder().decode(SessionInfo.self, from: jsonData) else {
                    handle(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: ErrorMessage.cannotParseSession)))
                    return
                }
                
                if let session = GigyaSession(sessionToken: sessionInfo.sessionToken,
                                              secret: sessionInfo.sessionSecret,
                                              expiration: sessionInfo.expiration) {
                    
                    instance.setSession(session)
                    OwnID.CoreSDK.logger.log(level: .debug, type: Self.self)
                    promise(.success(OwnID.LoginResult(operationResult: VoidOperationResult(), authType: payload.authType)))
                } else {
                    handle(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: ErrorMessage.cannotInitSession)))
                }
            }
            .eraseToAnyPublisher()
        }
    }
}
