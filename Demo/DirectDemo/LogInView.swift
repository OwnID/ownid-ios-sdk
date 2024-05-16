import SwiftUI
import OwnIDCoreSDK

struct LogInView: View {
    @ObservedObject private var viewModel = LogInViewModel()
    
    var body: some View {
        VStack {
            fields()
                .zIndex(1)
            BlueButton(text: "Log in", action: viewModel.logIn)
            Text(viewModel.errorMessage)
                .font(.headline)
                .foregroundColor(.red)
        }
        .fullScreenCover(item: $viewModel.loggedInModel) { model in
            AccountView(model: model)
        }
    }
}

private extension LogInView {
    
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
        OwnID.FlowsSDK.LoginView(viewModel: viewModel.ownIDViewModel, visualConfig: .init())
    }
}
