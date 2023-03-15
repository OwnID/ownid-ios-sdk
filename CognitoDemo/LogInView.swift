import SwiftUI
import OwnIDAmplifySDK

struct LogInView: View {
    @ObservedObject private var viewModel = LogInViewModel()
    
    var body: some View {
        VStack {
            fields()
                .zIndex(1)
            Text(viewModel.errorMessage)
                .font(.headline)
                .foregroundColor(.red)
        }
    }
}

private extension LogInView {
    
    @ViewBuilder
    func fields() -> some View {
        Group {
            VStack(alignment: .leading) {
                TextField("Email", text: $viewModel.email)
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
        }
    }
    
    @ViewBuilder
    func skipPasswordView() -> some View {
        OwnID.AmplifySDK.createLoginView(viewModel: viewModel.ownIDViewModel, visualConfig: .init(buttonViewConfig: .init(variant: .authButton)))
    }
}
