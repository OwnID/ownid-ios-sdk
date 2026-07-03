import SwiftUI

struct ScenarioNavigationLink<Destination: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var subtitle: String? = nil
    let destination: Destination

    init(title: String, subtitle: String? = nil, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.subtitle = subtitle
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            ScenarioRow(title: title, subtitle: subtitle)
        }
        .listRowBackground(colorScheme == .dark ? Color(hex: 0x111820) : nil)
    }
}
