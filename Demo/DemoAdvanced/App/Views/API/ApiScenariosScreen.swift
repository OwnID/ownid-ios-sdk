import SwiftUI

struct ApiScenariosScreen: View {
    @StateObject private var apiViewModel = ApiViewModel()

    var body: some View {
        DemoRootScreen(title: "APIs") {
            List {
                ScenarioNavigationLink(title: "Verification and Enroll") {
                    ApiVerificationEnrollScreen(viewModel: apiViewModel)
                }

                ScenarioNavigationLink(title: "Passkey Create and Enroll") {
                    ApiPasskeyCreateEnrollScreen(viewModel: apiViewModel)
                }

                ScenarioNavigationLink(title: "Passkey Assertions") {
                    ApiPasskeyAssertionsScreen(viewModel: apiViewModel)
                }

                ScenarioNavigationLink(title: "Discover and Login") {
                    ApiDiscoverLoginScreen(viewModel: apiViewModel)
                }

                ScenarioNavigationLink(title: "OIDC") {
                    ApiOidcScreen(viewModel: apiViewModel)
                }
            }
        }
    }
}
