import Foundation
import Combine
import UIKit

extension OwnID {
    final class Flow: NSObject, UIAdaptivePresentationControllerDelegate {
        private var viewController: FlowViewController!
        private var wrappers = [any FlowWrapper]()
        private var resultPublisher = OwnID.CoreSDK.WebBridgePublisher()
        private var bag = Set<AnyCancellable>()
        
        func start(options: EliteOptions?, providers: Providers?, eventWrappers: [any FlowWrapper]) {
            resultPublisher = OwnID.CoreSDK.WebBridgePublisher()
            
            let viewController = FlowViewController()
            self.viewController = viewController
            self.wrappers = combinedWrappers(providers: providers, eventWrappers: eventWrappers)
            
            viewController.flowView.webView.options = options
            viewController.flowView.webView.wrappers = wrappers
            viewController.flowView.webView.resultPublisher = resultPublisher
            
            viewController.presentationController?.delegate = self
            
            if let topViewController = UIApplication.topViewController() {
                topViewController.present(viewController, animated: true)
                OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .flowTriggered, category: .login))
            } else {
                OwnID.CoreSDK.logger.log(level: .warning, message: "Flow failed to start", type: Self.self)
            }
            
            resultPublisher.sink { result in
                if let flowEvent = result as? FlowEvent {
                    if flowEvent.action.isTerminal {
                        DispatchQueue.main.async {
                            if !viewController.isBeingDismissed {
                                viewController.dismiss(animated: true) {
                                    OwnID.CoreSDK.WebBridgeFlow.shared.sendTerminalAction(flowEvent: flowEvent)
                                }
                            }
                        }
                    }
                }
            }.store(in: &bag)
        }
        
        private func combinedWrappers(providers: Providers?, eventWrappers: [any FlowWrapper]) -> [any FlowWrapper] {
            var wrappers = [any FlowWrapper]()
            
            let globalProvidersWrappers = OwnID.CoreSDK.providers?.toWrappers() ?? []
            if let providers {
                let providersWrappers = providers.toWrappers()
                wrappers.append(contentsOf: providersWrappers)
                globalProvidersWrappers.forEach({ wrapper in
                    if !providersWrappers.contains(where: { type(of: $0) == type(of: wrapper) }) {
                        wrappers.append(wrapper)
                    }
                })
            } else {
                wrappers.append(contentsOf: globalProvidersWrappers)
            }
            
            wrappers.append(contentsOf: eventWrappers)
            wrappers.append(contentsOf: eventWrappersWithDefaults(eventWrappers: eventWrappers))
            
            return wrappers
        }
        
        private func eventWrappersWithDefaults(eventWrappers: [any FlowWrapper]) -> [any FlowWrapper] {
            var wrappers = [any FlowWrapper]()
            
            if eventWrappers.first(where: { $0 is OnCloseWrapper }) == nil {
                wrappers.append(OnCloseWrapper())
            }
            if eventWrappers.first(where: { $0 is OnErrorWrapper }) == nil {
                wrappers.append(OnErrorWrapper(onError: nil))
            }
            if eventWrappers.first(where: { $0 is OnFinishWrapper }) == nil {
                wrappers.append(OnFinishWrapper(onFinish: nil))
            }
            
            return wrappers
        }
        
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            let wrapper: OnCloseWrapper? = OwnID.wrapperByAction(.onClose, wrappers: wrappers)
            Task {
                await wrapper?.invoke(payload: VoidFlowPayload())
            }
        }
    }
}
