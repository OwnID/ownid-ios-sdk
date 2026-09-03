import SwiftUI

private enum DemoTab: CaseIterable, Hashable {
    case apis
    case operations
    case flows
    case headless

    var title: String {
        switch self {
        case .apis: return "APIs"
        case .operations: return "Ops"
        case .flows: return "Flows"
        case .headless: return "Headless"
        }
    }

    var systemImage: String {
        switch self {
        case .apis: return "curlybraces.square"
        case .operations: return "play.square"
        case .flows: return "square.stack.3d.up"
        case .headless: return "terminal"
        }
    }
}

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var authIntegration = DemoAuthIntegrationProvider.integration

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        Group {
            if authIntegration.currentSession != nil {
                currentUserContainer()
            } else {
                DemoTabsView()
            }
        }
        .tint(palette.primary)
        .accentColor(palette.primary)
    }

    @ViewBuilder
    private func currentUserContainer() -> some View {
        if #available(iOS 16.0, *) {
            NavigationStack { currentUserContent() }
        } else {
            NavigationView { currentUserContent() }
                .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    private func currentUserContent() -> some View {
        CurrentUserScreen(
            loadCurrentUser: authIntegration.loadCurrentUser,
            onLogout: authIntegration.signOut
        )
    }
}

private struct DemoTabsView: View {
    @State private var selectedTab = DemoTab.apis
    @State private var tabIDs = Dictionary(uniqueKeysWithValues: DemoTab.allCases.map { ($0, UUID()) })

    var body: some View {
        TabView(selection: selectedTabBinding) {
            DemoNavigationContainer { ApiScenariosScreen() }
                .id(tabIDs[.apis])
                .tabItem { Label(DemoTab.apis.title, systemImage: DemoTab.apis.systemImage) }
                .tag(DemoTab.apis)

            DemoNavigationContainer { OperationScenariosScreen() }
                .id(tabIDs[.operations])
                .tabItem { Label(DemoTab.operations.title, systemImage: DemoTab.operations.systemImage) }
                .tag(DemoTab.operations)

            DemoNavigationContainer { FlowScenariosScreen() }
                .id(tabIDs[.flows])
                .tabItem { Label(DemoTab.flows.title, systemImage: DemoTab.flows.systemImage) }
                .tag(DemoTab.flows)

            DemoNavigationContainer { HeadlessScreen() }
                .id(tabIDs[.headless])
                .tabItem { Label(DemoTab.headless.title, systemImage: DemoTab.headless.systemImage) }
                .tag(DemoTab.headless)
        }
    }

    private var selectedTabBinding: Binding<DemoTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if selectedTab != newValue {
                    tabIDs[selectedTab] = UUID()
                }
                selectedTab = newValue
            }
        )
    }
}

private struct DemoNavigationContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        navigationContainer
    }

    @ViewBuilder
    private var navigationContainer: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}
