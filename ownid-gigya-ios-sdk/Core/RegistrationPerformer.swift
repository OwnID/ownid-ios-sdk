import OwnIDCoreSDK
import Gigya
import Combine
import SwiftUI

public extension OwnID.GigyaSDK {
    enum Registration {}
}

extension OwnID.GigyaSDK.Registration {
    public typealias PublisherType = AnyPublisher<OwnID.RegisterResult, OwnID.CoreSDK.Error>
    
    public struct Parameters: RegisterParameters {
        public init(parameters: [String: Any]) {
            self.parameters = parameters
        }
        
        public let parameters: [String: Any]
    }
}

extension OwnID.GigyaSDK.Registration {
    final class Performer<T: GigyaAccountProtocol>: RegistrationPerformer {
        init(instance: GigyaCore<T>) {
            self.instance = instance
        }
        
        let instance: GigyaCore<T>
        
        func register(configuration: OwnID.FlowsSDK.RegistrationConfiguration, parameters: RegisterParameters) -> PublisherType {
            OwnID.GigyaSDK.Registration.register(instance: instance,
                                                 configuration: configuration,
                                                 parameters: parameters)
        }
    }
}

extension OwnID.GigyaSDK.Registration {
    static func register<T: GigyaAccountProtocol>(instance: GigyaCore<T>,
                                                  configuration: OwnID.FlowsSDK.RegistrationConfiguration,
                                                  parameters: RegisterParameters) -> PublisherType {
        Future<OwnID.RegisterResult, OwnID.CoreSDK.Error> { promise in
            func handle(error: OwnID.CoreSDK.Error, customErrorMessage: String? = nil) {
                OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self).log(customErrorMessage: customErrorMessage)
                promise(.failure(error))
            }
            
            let gigyaParameters = parameters as? OwnID.GigyaSDK.Registration.Parameters ?? OwnID.GigyaSDK.Registration.Parameters(parameters: [:])
            var registerParams = gigyaParameters.parameters
            
            var dataJson: [String: Any]
            if let data = registerParams["data"] as? [String: Any] {
               dataJson = data
            } else {
                dataJson = [:]
            }
            
            guard let metadata = configuration.payload.metadata,
                  let dataField = (metadata as? [String: Any])?["dataField"] as? String
            else {
                let message = OwnID.GigyaSDK.ErrorMessage.cannotParseRegistrationMetadataParameter
                handle(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)))
                return
            }
            
            let data = Data((configuration.payload.data ?? "").utf8)
            let ownIDDataJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            dataJson[dataField] = ownIDDataJson
            registerParams["data"] = dataJson
            
            if var language = configuration.payload.requestLanguage {
                language = String(language.prefix(2))
                addLocaleToParams(locale: language, params: &registerParams)
            }
            
            instance.register(email: configuration.loginId,
                              password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                              params: registerParams
            ) { result in
                switch result {
                case .success(let account):
                    let UID = account.UID ?? ""
                    OwnID.CoreSDK.logger.log(level: .debug,
                                             message: "UID \(UID.logValue)",
                                             type: Self.self)
                    promise(.success(OwnID.RegisterResult(operationResult: VoidOperationResult(),
                                                          authType: configuration.payload.authType)))
                    
                case .failure(let error):
                    switch error.error {
                    case .gigyaError(let data):
                        let code = data.errorCode
                        if OwnID.GigyaSDK.ErrorMapper.allowedActionsErrorCodes.contains(code) {
                            let message = "Registration: [\(code)] \(data.errorMessage ?? "")"
                            OwnID.CoreSDK.logger.log(level: .warning, message: message, type: Self.self)
                            promise(.failure(.integrationError(underlying: error.error)))
                        } else {
                            handle(error: .integrationError(underlying: error.error),
                                   customErrorMessage: OwnID.GigyaSDK.gigyaErrorMessage(error.error))
                        }
                        
                    default:
                        handle(error: .integrationError(underlying: error.error),
                               customErrorMessage: OwnID.GigyaSDK.gigyaErrorMessage(error.error))
                    }
                }
            }
        }
        .map { $0 as OwnID.RegisterResult }
        .eraseToAnyPublisher()
    }
    
    private static func addLocaleToParams(locale: String, params: inout [String: Any]) {
        if var existingProfile = params["profile"] as? [String: Any] {
            if (existingProfile["locale"] == nil) {
                existingProfile["locale"] = locale
                params["profile"] = existingProfile
            }
        } else if params["profile"] != nil {
            return
        } else {
            let localeField = ["locale": locale]
            params["profile"] = localeField
        }
    }
}
