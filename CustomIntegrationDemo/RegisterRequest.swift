import Foundation
import Combine
import OwnIDCoreSDK

struct RegisterRequest {
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
                guard data.isEmpty else {
                    return Fail(error: .coreLog(entry: .errorEntry(Self.self), error: .payloadMissing(underlying: String(data: data, encoding: .utf8))))
                        .eraseToAnyPublisher()
                }
                return LoginRequest.login(ownIdData: ownIdData, password: password, email: email)
                    .map { loginResult -> OwnID.RegisterResult in
                        OwnID.RegisterResult(operationResult: loginResult.operationResult)
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    private static func urlSessionRequest(for payloadDict: [String: Any]) -> AnyPublisher<URLSession.DataTaskPublisher.Output, OwnID.CoreSDK.CoreErrorLogWrapper> {
        return Just(payloadDict)
            .setFailureType(to: OwnID.CoreSDK.Error.self)
            .eraseToAnyPublisher()
            .tryMap { try JSONSerialization.data(withJSONObject: $0) }
            .map { payloadData -> URLRequest in
                var request = URLRequest(url: URL(string: "https://node-mongo.custom.demo.dev.ownid.com/api/auth/register")!)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpMethod = "POST"
                request.httpBody = payloadData
                return request
            }
            .eraseToAnyPublisher()
            .flatMap { request -> AnyPublisher<URLSession.DataTaskPublisher.Output, Error> in
                URLSession.shared.dataTaskPublisher(for: request)
                    .mapError { $0 as Error }
                    .eraseToAnyPublisher()
            }
            .mapError { .coreLog(entry: .errorEntry(Self.self), error: .plugin(underlying: CustomIntegrationDemoError.registerRequestFailed(underlying: $0))) }
            .eraseToAnyPublisher()
    }
}
