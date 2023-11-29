import OwnIDCoreSDK
import Gigya
import Combine
import SwiftUI

public extension OwnID.GigyaSDK {
    enum Registration {}
}

extension OwnID.GigyaSDK.Registration {
    public typealias PublisherType = AnyPublisher<OwnID.RegisterResult, OwnID.CoreSDK.CoreErrorLogWrapper>
    
    public struct Parameters: RegisterParameters {
        public init(parameters: [String: Any]) {
            self.parameters = parameters
        }
        
        public let parameters: [String: Any]
    }
}

extension OwnID.GigyaSDK.Registration {
    final class Performer<T: GigyaAccountProtocol>: RegistrationPerformer {
        init(instance: GigyaCore<T>, sdkConfigurationName: String) {
            self.instance = instance
            self.sdkConfigurationName = sdkConfigurationName
        }
        
        let instance: GigyaCore<T>
        let sdkConfigurationName: String
        
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
        Future<OwnID.RegisterResult, OwnID.CoreSDK.CoreErrorLogWrapper> { promise in
            func handle(error: OwnID.CoreSDK.Error) {
                promise(.failure(.coreLog(error: error, type: Self.self)))
            }
            
            let gigyaParameters = parameters as? OwnID.GigyaSDK.Registration.Parameters ?? OwnID.GigyaSDK.Registration.Parameters(parameters: [:])
            guard let metadata = configuration.payload.metadata,
                  let dataField = (metadata as? [String: Any])?["dataField"] as? String
            else {
                let message = OwnID.GigyaSDK.ErrorMessage.cannotParseRegistrationMetadataParameter
                handle(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)))
                return
            }
            
            var registerParams = gigyaParameters.parameters
            let ownIDParameters = [dataField: configuration.payload.dataContainer]
            registerParams["data"] = ownIDParameters
            
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
                                                    Self.self)
                    promise(.success(OwnID.RegisterResult(operationResult: VoidOperationResult(),
                                                          authType: configuration.payload.authType)))
                    
                case .failure(let error):
                    OwnID.GigyaSDK.ErrorMapper.mapRegistrationError(error: error,
                                                                    context: configuration.payload.context,
                                                                    loginId: configuration.loginId,
                                                                    authType: configuration.payload.authType)
                    var json: [String: Any]?
                    if case let .gigyaError(data) = error.error {
                        json = data.toDictionary()
                    }
                    let error = OwnID.GigyaSDK.IntegrationError.gigyaSDKError(gigyaError: error.error, dataDictionary: json)
                    handle(error: .integrationError(underlying: error))
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
