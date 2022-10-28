import UIKit
import Gigya
import SwiftUI
import Combine
import DemoComponents

struct ScreenSets: UIViewControllerRepresentable {
    let screensetResult: PassthroughSubject<GigyaPluginEvent<OwnIDAccount>, Never>
    
    func makeUIViewController(context: Context) -> ScreenSetsVC {
        let vc = ScreenSetsVC()
        vc.screensetResult = screensetResult
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ScreenSetsVC, context: Context) { }
}

public struct ScreenSetsView: View {
    let screensetResult: PassthroughSubject<GigyaPluginEvent<OwnIDAccount>, Never>
    
    public var body: some View {
        ScreenSets(screensetResult: screensetResult)
    }
}

final class ScreenSetsVC: UIViewController {
    let appConfig = AppConfiguration<GigyaServerConfig>()
    var screensetResult: PassthroughSubject<GigyaPluginEvent<OwnIDAccount>, Never>!
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        GigyaShared.instance.showScreenSet(with: appConfig.config.screenSet, viewController: self) { [self] result in
            screensetResult.send(result)
        }
    }
}
