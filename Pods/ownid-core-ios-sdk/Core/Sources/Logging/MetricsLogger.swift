import Combine
import Foundation

public extension OwnID.CoreSDK {
    final class MetricsLogger: ExtensionLoggerProtocol {
        public let identifier = UUID()
        private let provider: APIProvider
        private var bag = Set<AnyCancellable>()
        
        init(provider: APIProvider = URLSession.loggerSession) {
            self.provider = provider
        }
        
        public func log(_ entry: StandardMetricLogEntry) {
            sendEvent(for: entry)
        }
    }
}

private extension OwnID.CoreSDK.MetricsLogger {
    func sendEvent(for entry: OwnID.CoreSDK.StandardMetricLogEntry) {
        Just(entry)
            .map { entry -> OwnID.CoreSDK.StandardMetricLogEntry in
                entry.metadata[OwnID.CoreSDK.LoggerValues.correlationIDKey] = OwnID.CoreSDK.LoggerValues.instanceID.uuidString
                return entry
            }
            .eraseToAnyPublisher()
            .encode(encoder: JSONEncoder())
            .map { body -> URLRequest in
                var request = URLRequest(url: OwnID.CoreSDK.shared.metricsURL)
                request.httpMethod = "POST"
                request.httpBody = body
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                return request
            }
            .flatMap { [self] request in
                provider.apiResponse(for: request).mapError { $0 as Swift.Error }
            }
            .eraseToAnyPublisher()
            .ignoreOutput()
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &bag)
    }
}
