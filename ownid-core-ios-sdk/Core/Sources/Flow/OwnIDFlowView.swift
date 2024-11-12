import Foundation
import SwiftUI

extension OwnID {
    final class FlowViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
        private var hostingController: UIHostingController<FlowView>!
        var flowView = FlowView()
        
        override func viewDidLoad() {
            super.viewDidLoad()
            
            let hostingController = UIHostingController(rootView: flowView)
            self.hostingController = hostingController
            
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.didMove(toParent: self)
            
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
    
    struct FlowView: View {
        var webView = OwnIDFlowWebView()
        
        var body: some View {
            webView
        }
    }
}
