import SwiftUI

struct BoostFlowScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    let onPasswordLogin: (String, String) async throws -> Void
    let onRegister: (String, String, String, String?) async throws -> Void

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        ScrollView {
            VStack(spacing: 16) {
                DemoHeaderView(title: "Boost Flow", onBack: { dismiss() })

                Picker("Boost Mode", selection: $selectedTab) {
                    Text("Login").tag(0)
                    Text("Register").tag(1)
                }
                .pickerStyle(.segmented)

                ZStack(alignment: .top) {
                    BoostLoginTab(onPasswordLogin: onPasswordLogin)
                        .opacity(selectedTab == 0 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 0)
                        .accessibilityHidden(selectedTab != 0)

                    BoostCreatePasskeyTab(onRegister: onRegister)
                        .opacity(selectedTab == 1 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 1)
                        .accessibilityHidden(selectedTab != 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .demoContentWidth()
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}
