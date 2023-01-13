import Foundation
import Combine
import OwnIDCoreSDK

struct LoginResponse: Decodable {
    let token: String
}

extension String: OperationResult { }

enum CustomIntegrationDemoError: PluginError {
    case loginRequestFailed(underlying: Error)
    case registerRequestFailed(underlying: Error)
}

struct LoginRequest {
    static func login(ownIdData: Any?,
                      password: String? = .none,
                      email: String) -> OwnID.LoginResultPublisher {
        if let ownIdData = ownIdData as? [String: String], let token = ownIdData["token"] {
            return Just(OwnID.LoginResult(operationResult: token))
                .setFailureType(to: OwnID.CoreSDK.Error.self)
                .eraseToAnyPublisher()
        }
        let payloadDict = ["email": email, "password": password]
        return Just(payloadDict)
            .setFailureType(to: OwnID.CoreSDK.Error.self)
            .eraseToAnyPublisher()
            .tryMap { try JSONSerialization.data(withJSONObject: $0) }
            .map { payloadData -> URLRequest in
                var request = URLRequest(url: URL(string: "https://node-mongo.custom.demo.dev.ownid.com/api/auth/login")!)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpMethod = "POST"
                request.httpBody = payloadData
                return request
            }
            .flatMap {
                URLSession.shared.dataTaskPublisher(for: $0)
                    .mapError { $0 as Error }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
            .map { $0.data }
            .decode(type: LoginResponse.self, decoder: JSONDecoder())
            .map { OwnID.LoginResult(operationResult: $0.token) }
            .receive(on: DispatchQueue.main)
            .mapError { OwnID.CoreSDK.Error.plugin(error: CustomIntegrationDemoError.loginRequestFailed(underlying: $0)) }
            .eraseToAnyPublisher()
    }
}
