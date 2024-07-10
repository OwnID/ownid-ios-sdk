import SwiftUI

public struct WelcomeView: View {
    @ObservedObject var viewModel: WelcomeViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    
    @State private var isLoginActive = false
    @State private var isRegisterActive = false
    
    init(coordinator: AppCoordinator) {
        viewModel = WelcomeViewModel(coordinator: coordinator)
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    HeaderView()
                    Spacer()
                }
                .ignoresSafeArea()
                VStack {
                    Text("Welcome to OwnID Demo App")
                        .font(.system(size: 20))
                        .padding(.top, 30)
                    Group {
                        NavigationLink(destination: RegisterView(),
                                       isActive: $isRegisterActive) {
                            BlueButton(text: "Register") {
                                self.isRegisterActive = true
                            }
                        }
                        NavigationLink(destination: LogInView(),
                                       isActive: $isLoginActive) {
                            BlueButton(text: "Login") {
                                self.isLoginActive = true
                            }
                        }
                        BlueButton(text: "Start Flow", action: viewModel.startFlow)
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    Text(viewModel.errorMessage ?? "")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                }
                if let loginId = viewModel.notFoundLoginId {
                    ProfileCollectionView(coordinator: coordinator, loginId: loginId, closeClosure: {
                        viewModel.notFoundLoginId = nil
                    })
                }
            }
        }
    }
}
