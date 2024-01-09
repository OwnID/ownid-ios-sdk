import SwiftUI
import OwnIDCoreSDK
import OwnIDGigyaSDK

struct RegisterView: View {
    @ObservedObject private var viewModel = RegisterViewModel()
    
    var body: some View {
        content()
    }
}

private extension RegisterView {
    
    @ViewBuilder
    func content() -> some View {
        VStack {
            fields()
                .zIndex(1)
            Button("Create Account", action: viewModel.register)
            Text(viewModel.errorMessage)
                .font(.headline)
                .foregroundColor(.red)
        }
        .fullScreenCover(item: $viewModel.loggedInModel) { model in
            AccountView(model: model)
        }
    }
    
    func fields() -> some View {
        Group {
            VStack(alignment: .leading) {
                TextField("First name", text: $viewModel.firstName)
                    .textContentType(.givenName)
                    .keyboardType(.alphabet)
                    .padding(.bottom, 9)
                TextField("Email", text: $viewModel.email)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
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
            }
    }
    
    func skipPasswordView() -> some View {
        OwnID.GigyaSDK.createRegisterView(viewModel: viewModel.ownIDViewModel)
    }
}
