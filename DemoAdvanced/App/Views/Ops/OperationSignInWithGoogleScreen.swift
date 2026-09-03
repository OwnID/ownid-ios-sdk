import SwiftUI

struct OperationSignInWithGoogleScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: OperationViewModel

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(accessTokenStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Button("Start Sign In with Google Operation") {
                    viewModel.startSignInWithGoogleOperation()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)

                LogView(log: viewModel.log)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Operations / Sign In with Google")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accessTokenStatusText: String {
        if viewModel.screenState.accessToken == nil {
            return "Operation will start without an access token."
        } else {
            return "Current access token will be passed to the operation context."
        }
    }
}
