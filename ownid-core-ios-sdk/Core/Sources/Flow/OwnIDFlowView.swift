import Foundation
import SwiftUI

extension OwnID {
    final class FlowViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
        private var hostingController: UIViewController!
        var flowView = FlowView()
        
        override func viewDidLoad() {
            super.viewDidLoad()
            
            let hostingController = UIHostingController(rootView: flowView)
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.view.frame = view.bounds
            hostingController.didMove(toParent: self)
            hostingController.presentationController?.delegate = self
            self.hostingController = hostingController
        }
    }
    
    struct FlowView: View {
        var webView = OwnIDFlowWebView()
        
        var body: some View {
            webView
        }
    }
}

