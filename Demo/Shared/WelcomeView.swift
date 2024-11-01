import SwiftUI

public struct WelcomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var viewModel = WelcomeViewModel()
    
    @State private var isLoginActive = false
    @State private var isRegisterActive = false
    @State private var errorMessage = ""
    @State private var notFoundLoginId: String?
    
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
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top)
                }
                if let loginId = notFoundLoginId {
                    ProfileCollectionView(coordinator: coordinator, loginId: loginId, closeClosure: {
                        notFoundLoginId = nil
                    })
                }
            }
        }
        .onChange(of: viewModel.flowResult) { result in
            DispatchQueue.main.async {
                if let result {
                    switch result {
                    case .profileCollect(let params):
                        notFoundLoginId = params?["loginId"] as? String
                    case .close:
                        break
                    case .error(let error):
                        errorMessage = error.localizedDescription
                    case .loggedIn(let account):
                        if let model = account {
                            coordinator.showLoggedIn(model: model)
                        }
                    }
                }
            }
        }
    }
}
