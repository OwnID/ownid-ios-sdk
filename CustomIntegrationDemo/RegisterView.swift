import SwiftUI
import OwnIDCoreSDK
import AccountView

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
            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .keyboardType(.emailAddress)
                .disabled(viewModel.isOwnIDEnabled)
            
                skipPasswordView()
                    .layoutPriority(1)
                    .zIndex(1)
            }
    }
    
    func skipPasswordView() -> some View {
        OwnID.FlowsSDK.RegisterView(viewModel: viewModel.ownIDViewModel,
                                 usersEmail: $viewModel.email,
                                 visualConfig: OwnID.UISDK.VisualLookConfig())
    }
}
