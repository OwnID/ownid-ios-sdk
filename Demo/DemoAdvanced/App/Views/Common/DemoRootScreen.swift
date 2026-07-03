import SwiftUI

struct DemoRootScreen<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        VStack(spacing: 0) {
            DemoRootHeader(title: title)

            rootContent(palette: palette)
                .frame(maxWidth: 480, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .demoNavigationBarHidden()
    }

    @ViewBuilder
    private func rootContent(palette: Palette) -> some View {
        if #available(iOS 17.0, *) {
            content
                .contentMargins(.top, 6, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(palette.background)
        } else if #available(iOS 16.0, *) {
            content
                .scrollContentBackground(.hidden)
                .background(palette.background)
        } else {
            content
                .background(palette.background)
        }
    }
}
