import Combine
import Foundation
 
public protocol EventProtocol {
    func sendMetric(_ metric: OwnID.CoreSDK.Metric)
}

public extension OwnID.CoreSDK {
    final class EventService: EventProtocol {
        private let provider: APIProvider
        private let sessionService: SessionService
        private var bag = Set<AnyCancellable>()

        private let queue = DispatchQueue(label: "\(EventService.self).\(OperationQueue.self)")
        private let semaphore = DispatchSemaphore(value: 1)
        
        static let shared = EventService()
        
        init(provider: APIProvider = URLSession.loggerSession) {
            self.provider = provider
            self.sessionService = SessionService(provider: provider)
        }
        
        public func log(_ entry: LogItem) {
            sendEvent(for: entry)
        }
        
        public func sendMetric(_ metric: Metric) {
            sendEvent(for: metric)
        }
    }
}

private extension OwnID.CoreSDK.EventService {
    func sendEvent(for entry: Encodable) {
        queue.async {
            self.semaphore.wait()
            
            if let url = OwnID.CoreSDK.shared.apiBaseURL?.appendingPathComponent("events") {
                self.sessionService.perform(url: url, method: .post, body: entry, headers: ["Content-Type": "application/json"])
                    .ignoreOutput()
                .sink(receiveCompletion: { _ in
                    self.semaphore.signal()
                }, receiveValue: { _ in })
                .store(in: &self.bag)
            }
        }
    }
}
