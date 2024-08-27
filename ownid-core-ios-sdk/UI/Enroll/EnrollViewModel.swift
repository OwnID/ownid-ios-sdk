import Combine
import Foundation

extension OwnID.UISDK.Enroll {
    final class ViewModel: ObservableObject {
        private enum Constants {
            static let metricName = "Device Enrollment"
        }
        
        @Published var isLoading = false
        private let store: Store<ViewState, Action>
        private let loginId: String
        private let sourceMetricName: String
        private let eventService: EventProtocol
        
        private var storeCancellable: AnyCancellable?
        private var bag = Set<AnyCancellable>()
        
        init(store: Store<ViewState, Action>, 
             loginId: String,
             sourceMetricName: String,
             eventService: EventProtocol = OwnID.CoreSDK.eventService) {
            self.store = store
            self.loginId = loginId
            self.sourceMetricName = sourceMetricName
            self.eventService = eventService
            
            storeCancellable = store.$value
                .map { $0.isLoading }
                .sink { [weak self] isLoading in
                    self?.isLoading = isLoading
                }
            
            store.send(.viewLoaded)
            
            eventService.sendMetric(.trackMetric(action: .screenShow(screen: Constants.metricName),
                                                 category: .general,
                                                 loginId: loginId,
                                                 source: sourceMetricName))
        }
        
        func continueFlow() {
            eventService.sendMetric(.clickMetric(action: .clickEnroll,
                                                 category: .general,
                                                 loginId: loginId,
                                                 source: sourceMetricName))
            
            store.send(.continueFlow)
        }
        
        func handleNotNow() {
            eventService.sendMetric(.clickMetric(action: .notNow,
                                                 category: .general,
                                                 loginId: loginId,
                                                 source: sourceMetricName))
            
            OwnID.CoreSDK.LoginIdDataSaver.save(loginId: loginId, lastEnrollmentTimeInterval: Date().timeIntervalSince1970)
            
            store.send(.notNow)
        }
        
        func dismiss() {
            eventService.sendMetric(.clickMetric(action: .close,
                                                 category: .general,
                                                 loginId: loginId,
                                                 source: sourceMetricName))
            
            store.send(.cancel)
        }
    }
}
