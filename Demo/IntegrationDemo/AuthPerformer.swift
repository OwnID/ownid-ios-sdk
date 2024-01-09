import Foundation
import Combine
import OwnIDCoreSDK

final class Login: LoginPerformer {
    func login(payload: OwnID.CoreSDK.Payload,
               loginId: String) -> OwnID.LoginResultPublisher {
        CustomAuthSystem.login(ownIdData: payload.data, email: loginId)
    }
}

final class Registration: RegistrationPerformer {
    func register(configuration: OwnID.FlowsSDK.RegistrationConfiguration, parameters: RegisterParameters) -> OwnID.RegistrationResultPublisher {
        let ownIdData = configuration.payload.data
        return CustomAuthSystem.register(ownIdData: ownIdData as? String,
                                         password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                                         email: configuration.loginId,
                                         name: (parameters as? RegistrationParameters)?.firstName ?? "no name")
    }
}

final class RegistrationParameters: RegisterParameters {
    internal init(firstName: String) {
        self.firstName = firstName
    }
    
    let firstName: String
}
