import SwiftUI
import Gigya
import AccountView

struct LogInView: View {
    @ObservedObject var viewModel = LogInViewModel()
    @State private var isLoginButtonPressed = false
    
    var body: some View {
        content()
    }
}

private extension LogInView {
    
    @ViewBuilder
    func content() -> some View {
        VStack {
            Text("OwnID Demo\nGigya Screensets")
                .font(.title)
                .multilineTextAlignment(.center)
                .padding()
            Text("OwnID enables your users to create a digital identity on their phone to instantly login to your websites or apps.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
            if isLoginButtonPressed {
                ScreenSetsView(screensetResult: viewModel.screensetResult)
            }
            Text(viewModel.errorMessage)
                .font(.headline)
                .foregroundColor(.red)
            Button("Sign In", action: { isLoginButtonPressed.toggle() })
        }
        .fullScreenCover(item: $viewModel.loggedInModel) { model in
            AccountView(model: model)
        }
    }
}

