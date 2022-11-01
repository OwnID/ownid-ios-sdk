import UIKit
import Gigya
import SwiftUI
import Combine

struct ScreenSets: UIViewControllerRepresentable {
    let screensetResult: PassthroughSubject<GigyaPluginEvent<GigyaAccount>, Never>
    
    func makeUIViewController(context: Context) -> ScreenSetsVC {
        let vc = ScreenSetsVC()
        vc.screensetResult = screensetResult
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ScreenSetsVC, context: Context) { }
}

public struct ScreenSetsView: View {
    let screensetResult: PassthroughSubject<GigyaPluginEvent<GigyaAccount>, Never>
    
    public var body: some View {
        ScreenSets(screensetResult: screensetResult)
    }
}

final class ScreenSetsVC: UIViewController {
    var screensetResult: PassthroughSubject<GigyaPluginEvent<GigyaAccount>, Never>!
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Gigya.sharedInstance().showScreenSet(with: "Default-RegistrationLogin", viewController: self) { [self] result in
            screensetResult.send(result)
        }
    }
}
