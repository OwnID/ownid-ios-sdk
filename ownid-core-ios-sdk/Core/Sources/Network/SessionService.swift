import Foundation
import Combine

extension OwnID.CoreSDK {
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }
}

extension OwnID.CoreSDK {
    class SessionService {
        let provider: APIProvider
        let supportedLanguages: Languages?
        
        init(provider: APIProvider = URLSession.shared,
             supportedLanguages: Languages? = nil) {
            self.provider = provider
            self.supportedLanguages = supportedLanguages
        }
        
        func perform<Body: Encodable, Response: Decodable>(url: ServerURL,
                                                           method: HTTPMethod,
                                                           body: Body,
                                                           headers: [String: String] = [:],
                                                           with type: Response.Type,
                                                           queue: OperationQueue = OperationQueue()) -> AnyPublisher<Response, Error> {
            performRequest(url: url, method: method, body: body, headers: headers, queue: queue)
                .tryMap { [self] response -> Data in
                    guard !response.data.isEmpty else {
                        let message = ErrorMessage.emptyResponseData
                        throw OwnID.CoreSDK.Error.userError(errorModel: UserErrorModel(message: message))
                    }
                    self.printResponse(data: response.data)
                    return response.data
                }
                .eraseToAnyPublisher()
                .decode(type: type, decoder: JSONDecoder())
                .mapError { error in
                    if let ownIDError = error as? OwnID.CoreSDK.Error {
                        return ownIDError
                    }
                    
                    let message = OwnID.CoreSDK.ErrorMessage.decodingError(description: error.localizedDescription)
                    return .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                }
                .eraseToAnyPublisher()
        }
        
        func perform<Body: Encodable>(url: ServerURL,
                                      method: HTTPMethod,
                                      body: Body,
                                      headers: [String: String] = [:],
                                      queue: OperationQueue = OperationQueue()) -> AnyPublisher<[String: Any], Error> {
            performRequest(url: url, method: method, body: body, headers: headers, queue: queue)
                .tryMap { [self] response -> [String: Any] in
                    let json = try JSONSerialization.jsonObject(with: response.data) as? [String : Any]
                    self.printResponse(data: response.data)
                    return json ?? [:]
                }
                .eraseToAnyPublisher()
                .mapError { error in
                    if let ownIDError = error as? OwnID.CoreSDK.Error {
                        return ownIDError
                    }
                    
                    let message = OwnID.CoreSDK.ErrorMessage.decodingError(description: error.localizedDescription)
                    return .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                }
                .eraseToAnyPublisher()
        }
        
        private func performRequest<Body: Encodable>(url: ServerURL,
                                                     method: HTTPMethod,
                                                     body: Body,
                                                     headers: [String: String],
                                                     queue: OperationQueue) -> AnyPublisher<URLSession.DataTaskPublisher.Output, Error> {
            Just(body)
                .subscribe(on: queue)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .encode(encoder: JSONEncoder())
                .mapError { error in
                    let message = OwnID.CoreSDK.ErrorMessage.encodingError(description: error.localizedDescription)
                    return .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                }
                .map { [self] body -> URLRequest in
                    var mergedHeaders = URLRequest.defaultHeaders(supportedLanguages: supportedLanguages ?? .init(rawValue: []))
                    headers.forEach { key, value in mergedHeaders[key] = value }

                    return URLRequest.request(url: url, method: method, body: body, headers: mergedHeaders)
                }
                .eraseToAnyPublisher()
                .flatMap { [self] request -> AnyPublisher<URLSession.DataTaskPublisher.Output, Error> in
                    provider.apiResponse(for: request)
                        .mapError { .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: $0.localizedDescription)) }
                        .flatMap { output -> AnyPublisher<URLSession.DataTaskPublisher.Output, Error> in
                            guard let httpResponse = output.response as? HTTPURLResponse else {
                                let message = "Invalid (non-HTTP) response."
                                return Fail(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)))
                                    .eraseToAnyPublisher()
                            }
                            
                            guard (200..<300).contains(httpResponse.statusCode) else {
                                let serverErrorMessage = self.extractServerErrorMessage(from: output.data)
                                
                                let message = "Request failed (\(httpResponse.statusCode)): \(serverErrorMessage)"
                                
                                return Fail(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)))
                                    .eraseToAnyPublisher()
                            }

                            return Just(output)
                                .setFailureType(to: Error.self)
                                .eraseToAnyPublisher()
                        }
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }

        private func extractServerErrorMessage(from data: Data) -> String {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverMessage = jsonObject["code"] as? String {
                return serverMessage
            }
            return "An unknown error occurred."
        }
        
        private func printResponse(data: Data) {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String : Any]
            
            var bodyFields = ""
            json?.forEach({ key, value in
                bodyFields.append("     \(key): \(value)\n")
            })
//            print("Response")
//            print("----------------\n Body:\n\(bodyFields)----------------\n")
        }
    }
}
