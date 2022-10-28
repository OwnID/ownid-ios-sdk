import SwiftUI
import OwnIDCoreSDK
import DemoComponents

struct AppCoordinatorView: View {
    
    @ObservedObject var coordinator: AppCoordinator
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    HeaderView()
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .background(OwnID.Colors.darkBlue)
                    appContent()
                        .padding(.top)
                        .padding(.top)
                    Spacer()
                    footer()
                        .padding(.bottom)
                        .padding(.bottom)
                }
            }
            .background(UISharedColor.background)
            .edgesIgnoringSafeArea([.top, .bottom])
    }
}

private extension AppCoordinatorView {
    
    @ViewBuilder
    func appContent() -> some View {
        switch coordinator.state {
        case .loggedIn:
            LoggedInView(viewModel: coordinator.loggedInViewModel!)
                .padding(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
            
        case .loggedOut:
            LogInView(viewModel: coordinator.logInViewModel)
                .padding(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
                .background(Color.white)
                .cornerRadius(6)
                .padding()
        }
    }
}
