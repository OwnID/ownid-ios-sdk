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
                    guard !response.data.isEmpty else {
                        let message = ErrorMessage.emptyResponseData
                        throw OwnID.CoreSDK.Error.userError(errorModel: UserErrorModel(message: message))
                    }
                    let json = try JSONSerialization.jsonObject(with: response.data, options: []) as? [String : Any]
                    self.printResponse(data: response.data)
                    return json ?? [:]
                }
                .eraseToAnyPublisher()
                .mapError { error in
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
                    if let supportedLanguages {
                        let headers = URLRequest.defaultHeaders(supportedLanguages: supportedLanguages)
                        return URLRequest.request(url: url, method: method, body: body, headers: headers)
                    } else {
                        return URLRequest.request(url: url, method: method, body: body, headers: headers)
                    }
                }
                .eraseToAnyPublisher()
                .flatMap { [self] request -> AnyPublisher<URLSession.DataTaskPublisher.Output, Error> in
                    return provider.apiResponse(for: request)
                        .mapError { .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: $0.localizedDescription)) }
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }
        
        private func printResponse(data: Data) {
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String : Any]
            
            var bodyFields = ""
            json?.forEach({ key, value in
                bodyFields.append("     \(key): \(value)\n")
            })
//            print("Response")
//            print("----------------\n Body:\n\(bodyFields)----------------\n")
        }
    }
}
