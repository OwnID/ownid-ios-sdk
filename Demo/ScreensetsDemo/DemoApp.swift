import SwiftUI
import Gigya

@main
struct DemoApp: App {
    
    init() {
        Gigya.sharedInstance().initFor(apiKey: "3_O4QE0Kk7QstG4VGDPED5omrr8mgbTuf_Gim8V_Y19YDP75m_msuGtNGQz89X0KWP", apiDomain: "us1.gigya.com")
    }
    
    var body: some Scene {
        WindowGroup {
            LogInView()
                .padding(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
                .background(Color.white)
                .cornerRadius(6)
                .padding()
        }
    }
}
