import SwiftUI

struct OperationScenariosScreen: View {
    @State private var operationViewModel = OperationViewModel()

    var body: some View {
        DemoRootScreen(title: "Operations") {
            List {
                ScenarioNavigationLink(title: "Login ID Collect") {
                    OperationLoginIdCollectScreen(viewModel: operationViewModel)
                }

                ScenarioNavigationLink(title: "Verification") {
                    OperationVerificationScreen(viewModel: operationViewModel)
                }

                ScenarioNavigationLink(title: "Passkey Create and Enroll") {
                    OperationPasskeyCreateEnrollScreen(viewModel: operationViewModel)
                }

                ScenarioNavigationLink(title: "Passkey Assertions") {
                    OperationPasskeyAssertionsScreen(viewModel: operationViewModel)
                }

                ScenarioNavigationLink(title: "Discover and Login") {
                    OperationDiscoverLoginScreen(viewModel: operationViewModel)
                }

                ScenarioNavigationLink(title: "Sign In with Apple") {
                    OperationSignInWithAppleScreen(viewModel: operationViewModel)
                }

                ScenarioNavigationLink(title: "Sign In with Google") {
                    OperationSignInWithGoogleScreen(viewModel: operationViewModel)
                }
            }
        }
    }
}
