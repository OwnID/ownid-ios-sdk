import OwnIDCoreSDK
import Gigya
import Combine

extension OwnID.GigyaSDK.LoginPerformer: LoginPerformer { }

extension OwnID.GigyaSDK {
    final class LoginPerformer<T: GigyaAccountProtocol> {
        private let instance: GigyaCore<T>
        
        init(instance: GigyaCore<T>) {
            self.instance = instance
        }
        
        func login(payload: OwnID.CoreSDK.Payload, loginId: String) -> AnyPublisher<OwnID.LoginResult, OwnID.CoreSDK.Error> {
            OwnID.GigyaSDK.LogIn.logIn(instance: instance, payload: payload)
                .map { $0 as OwnID.LoginResult }
                .eraseToAnyPublisher()
        }
    }
}

