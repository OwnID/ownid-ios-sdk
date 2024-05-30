import SwiftUI
import OwnIDCoreSDK

struct RegisterView: View {
    @ObservedObject private var viewModel = RegisterViewModel()
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

private extension RegisterView {
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

    
    @ViewBuilder
    func content() -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack {
                    HeaderView()
                    Group {
                        fields()
                            .zIndex(1)
                            .padding(.top, proxy.size.height / 10)
                        BlueButton(text: "Create Account", action: viewModel.register)
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
    
    func fields() -> some View {
        Group {
            VStack(alignment: .leading) {
                TextField("First name", text: $viewModel.firstName)
                    .textContentType(.givenName)
                    .keyboardType(.alphabet)
                    .fieldStyle()
                    .padding(.bottom, 9)
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
                .disabled(viewModel.isOwnIDEnabled)
                .fieldStyle()
            }
    }
    
    func skipPasswordView() -> some View {
        OwnID.FlowsSDK.RegisterView(viewModel: viewModel.ownIDViewModel, visualConfig: .init())
    }
}
