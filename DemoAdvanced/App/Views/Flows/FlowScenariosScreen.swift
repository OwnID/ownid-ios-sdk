import SwiftUI

struct FlowScenariosScreen: View {
    private let authIntegration = DemoAuthIntegrationProvider.integration

    var body: some View {
        DemoRootScreen(title: "Flows") {
            List {
                ScenarioNavigationLink(title: "Boost Create Passkey") {
                    BoostCreatePasskeyScreen(onRegister: authIntegration.registerAndSignIn)
                }

                ScenarioNavigationLink(title: "Boost Login") {
                    BoostLoginScreen(onPasswordLogin: authIntegration.signIn)
                }

                ScenarioNavigationLink(title: "Elite") {
                    EliteFlowScreen()
                }
            }
        }
    }
}
