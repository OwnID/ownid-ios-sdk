import SwiftUI
import OwnIDGigyaSDK

struct LogInView: View {
    @ObservedObject private var viewModel = LogInViewModel()
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        page()
            .onDisappear(perform: {
                viewModel.reset()
            })
            .onChange(of: viewModel.loggedInModel) { value in
                if let model = value {
                    coordinator.showLoggedIn(model: model)
                }
            }
    }
}

private extension LogInView {
    @ViewBuilder
    func page() -> some View {
        switch viewModel.state {
        case .loading:
            content()
                .loading()
            
        case .initial:
            content()
        }
    }
    
    func content() -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack {
                    HeaderView()
                    Group {
                        fields()
                            .zIndex(1)
                            .padding(.top, proxy.size.height / 10)
                        BlueButton(text: "Log in", action: viewModel.logIn)
                        Text(viewModel.errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top)
                    }
                    .padding(.horizontal, 20)
                    Spacer()
                }
                .frame(minHeight: proxy.size.height)
            }
        }
        .edgesIgnoringSafeArea([.top, .bottom])
    }
    
    @ViewBuilder
    func fields() -> some View {
        Group {
            VStack(alignment: .leading) {
                TextField("Email", text: $viewModel.loginId)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .fieldStyle()
                    .padding(.bottom, 9)
                passwordField()
            }
            .padding(.bottom, 9)
        }
    }
    
    @ViewBuilder
    func passwordField() -> some View {
        HStack(spacing: 8) {
            skipPasswordView()
                .layoutPriority(1)
                .zIndex(1)
            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .keyboardType(.emailAddress)
                .fieldStyle()
        }
    }
    
    @ViewBuilder
    func skipPasswordView() -> some View {
        OwnID.GigyaSDK.createLoginView(viewModel: viewModel.ownIDViewModel)
    }
}
