import Foundation
import Combine
import OwnIDCoreSDK

final class AuthSystem {
    private static let baseURL = "..."
    
    static func register(ownIdData: String?,
                         password: String,
                         email: String,
                         name: String) -> OwnID.RegistrationResultPublisher {
        var payloadDict = ["email": email, "password": password, "name": name]
        if let ownIdData {
            payloadDict["ownIdData"] = ownIdData
        }
        return urlSessionRequest(for: payloadDict)
            .eraseToAnyPublisher()
            .flatMap { (data, response) -> OwnID.RegistrationResultPublisher in
                guard !data.isEmpty else {
                    let message = "Response data is empty"
                    let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                                        
                    return Fail(error: .integrationError(underlying: error)).eraseToAnyPublisher()
                }
                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String : Any]
                if let errors = json?["errors"] as? [String], let errorMessage = errors.first {
                    let error = IntegrationError.registrationDataError(message: errorMessage)
                    return Fail(error: .integrationError(underlying: error)).eraseToAnyPublisher()
                } else {
                    return Self.login(ownIdData: ownIdData, password: password, email: email)
                        .map { loginResult -> OwnID.RegisterResult in
                            OwnID.RegisterResult(operationResult: loginResult.operationResult)
                        }
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    private static func urlSessionRequest(for payloadDict: [String: Any]) -> AnyPublisher<URLSession.DataTaskPublisher.Output, OwnID.CoreSDK.Error> {
        return Just(payloadDict)
            .setFailureType(to: OwnID.CoreSDK.Error.self)
            .eraseToAnyPublisher()
            .tryMap { try JSONSerialization.data(withJSONObject: $0) }
            .mapError { OwnID.CoreSDK.Error.integrationError(underlying: $0) }
            .map { payloadData -> URLRequest in
                var request = URLRequest(url: URL(string: "\(baseURL)/register")!)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpMethod = "POST"
                request.httpBody = payloadData
                return request
            }
            .eraseToAnyPublisher()
            .flatMap {
                URLSession.shared.dataTaskPublisher(for: $0)
                    .mapError { OwnID.CoreSDK.Error.integrationError(underlying: $0) }
                    .eraseToAnyPublisher()
            }
            .mapError { .integrationError(underlying: $0) }
            .eraseToAnyPublisher()
    }
    
    static func login(ownIdData: String?,
                      password: String? = .none,
                      email: String) -> OwnID.LoginResultPublisher {
        let data = Data((ownIdData ?? "").utf8)
        if let dataJson = try? JSONSerialization.jsonObject(with: data) as? [String: String], let token = dataJson["token"] {
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
                var request = URLRequest(url: URL(string: "\(baseURL)/login")!)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpMethod = "POST"
                request.httpBody = payloadData
                return request
            }
            .flatMap {
                URLSession.shared.dataTaskPublisher(for: $0)
                    .mapError { OwnID.CoreSDK.Error.integrationError(underlying: $0) }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
            .map { $0.data }
            .decode(type: LoginResponse.self, decoder: JSONDecoder())
            .mapError { OwnID.CoreSDK.Error.integrationError(underlying: $0) }
            .map { OwnID.LoginResult(operationResult: $0.token) }
            .receive(on: DispatchQueue.main)
            .mapError { .integrationError(underlying: $0) }
            .eraseToAnyPublisher()
    }
    
    static func fetchUserData(previousResult: OperationResult) -> AnyPublisher<UserResponse, OwnID.CoreSDK.Error> {
        return Just(previousResult)
            .setFailureType(to: OwnID.CoreSDK.Error.self)
            .eraseToAnyPublisher()
            .map { previousResult -> URLRequest in
                var request = URLRequest(url: URL(string: "\(baseURL)/profile")!)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(previousResult)", forHTTPHeaderField: "Authorization")
                request.httpMethod = "GET"
                return request
            }
            .flatMap {
                URLSession.shared.dataTaskPublisher(for: $0)
                    .mapError { OwnID.CoreSDK.Error.integrationError(underlying: $0) }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
            .map { $0.data }
            .decode(type: UserResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .mapError { OwnID.CoreSDK.Error.integrationError(underlying: $0) }
            .eraseToAnyPublisher()
    }
}

struct LoginResponse: Decodable {
    let token: String
}

struct UserResponse: Decodable {
    let email: String
    let name: String
}

extension String: @retroactive OperationResult { }

enum IntegrationError: Error, LocalizedError {
    case registrationDataError(message: String)
    
    var errorDescription: String? {
        switch self {
        case .registrationDataError(let message):
            return message
        }
    }
}
