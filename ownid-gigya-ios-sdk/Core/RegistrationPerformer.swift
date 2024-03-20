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
        Future<OwnID.RegisterResult, OwnID.CoreSDK.Error> { promise in
            func handle(error: OwnID.GigyaSDK.Error) {
                switch error {
                case .gigyaSDKError(let error, _):
                    switch error {
                    case .gigyaError(let data):
                        let allowedActionsErrorCodes = [206001, 206002, 206006, 403102, 403101]
                        let gigyaError = data.errorCode
                        if !allowedActionsErrorCodes.contains(gigyaError) {
                            OwnID.CoreSDK.logger.logGigya(.errorEntry(context: nil, message: "error: \(error)", Self.self))
                        }
                    default:
                        OwnID.CoreSDK.logger.logGigya(.errorEntry(context: nil, message: "error: \(error)", Self.self))
                    }
                default:
                    OwnID.CoreSDK.logger.logGigya(.errorEntry(context: nil, message: "error: \(error)", Self.self))
                }
                promise(.failure(.plugin(error: error)))
            }
            
            guard configuration.email.isValid else { handle(error: .emailIsNotValid); return }
            let gigyaParameters = parameters as? OwnID.GigyaSDK.Registration.Parameters ?? OwnID.GigyaSDK.Registration.Parameters(parameters: [:])
            guard let metadata = configuration.payload.metadata,
                  let dataField = (metadata as? [String: Any])?["dataField"] as? String
            else { handle(error: .cannotParseRegistrationMetadataParameter); return }
            
            var registerParams = gigyaParameters.parameters
            let ownIDParameters = [dataField: configuration.payload.dataContainer]
            registerParams["data"] = ownIDParameters
            
            if var language = configuration.payload.requestLanguage {
                language = String(language.prefix(2))
                addLocaleToParams(locale: language, params: &registerParams)
            }
            
            instance.register(email: configuration.email.rawValue,
                              password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                              params: registerParams
            ) { result in
                switch result {
                case .success(let account):
                    let UID = account.UID ?? ""
                    OwnID.CoreSDK.logger.logGigya(.entry(context: configuration.payload.context, message: "UID \(UID.logValue)", Self.self))
                    promise(.success(OwnID.RegisterResult(operationResult: VoidOperationResult(), authType: configuration.payload.authType)))
                    
                case .failure(let error):
                    var json: [String: Any]?
                    if case let .gigyaError(data) = error.error {
                        json = data.toDictionary()
                    }
                    handle(error: .gigyaSDKError(error: error.error, dataDictionary: json))
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
