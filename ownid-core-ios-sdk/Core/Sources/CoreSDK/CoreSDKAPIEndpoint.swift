import Combine
import Foundation

extension OwnID.CoreSDK {
    struct APIEndpoint {
        var serverConfiguration: (URL) -> AnyPublisher<ServerConfiguration, Error>
    }
}

extension OwnID.CoreSDK.APIEndpoint {
    static let live = Self { url in
        var request = URLRequest(url: url)
        var headers: [String: String] = ["User-Agent": OwnID.CoreSDK.UserAgentManager.shared.SDKUserAgent]
        if let appUrl = OwnID.CoreSDK.shared.store.value.configuration?.appUrl { headers["X-OwnID-AppUrl"] = appUrl }
        request.allHTTPHeaderFields = headers
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .eraseToAnyPublisher()
            .mapError { OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: $0.localizedDescription)) }
            .retry(2)
            .map { data, _ in return data }
            .eraseToAnyPublisher()
            .decode(type: OwnID.CoreSDK.ServerConfiguration.self, decoder: JSONDecoder())
            .mapError { OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: $0.localizedDescription)) }
            .eraseToAnyPublisher()
    }
}

extension OwnID.CoreSDK.APIEndpoint {
    static let testMock = Self { _ in
        Just(.mock(isFailed: false))
            .setFailureType(to: OwnID.CoreSDK.Error.self)
            .eraseToAnyPublisher()
    }
}
