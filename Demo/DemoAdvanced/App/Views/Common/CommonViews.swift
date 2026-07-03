import Combine
import SwiftUI

struct ScenarioRow: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LogView: View {
    @ObservedObject var log: LogStore

    var body: some View {
        ScrollView {
            Text(log.text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content
    private let padding: EdgeInsets

    init(padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12), @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(padding)
        .background(palette.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var lines: [String] = []

    var text: String {
        lines.isEmpty ? "No logs yet." : lines.joined(separator: "\n")
    }

    func add(_ message: String) {
        lines.append(message)
    }

    func clear() {
        lines.removeAll()
    }
}

struct DemoRootHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        HStack(alignment: .center, spacing: 16) {
            Text("\((Bundle.main.bundleIdentifier!.components(separatedBy: ".").last)!.uppercased()): \(title)")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Image("OwnIDLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 124, height: 30)
                .foregroundStyle(palette.onSurface)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(palette.background)
    }
}

struct ScenarioPlaceholderScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        content(palette: palette)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(palette: Palette) -> some View {
        if #available(iOS 16.0, *) {
            List {}
                .scrollContentBackground(.hidden)
                .background(palette.background.ignoresSafeArea())
        } else {
            List {}
                .background(palette.background.ignoresSafeArea())
        }
    }
}

struct DemoFormFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = Theme.palette(for: colorScheme)

        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.fieldBackground))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = Theme.palette(for: colorScheme)

        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(isEnabled ? palette.onPrimary : palette.onSurfaceVariant.opacity(0.6))
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? palette.primary.opacity(configuration.isPressed ? 0.84 : 1.0) : palette.border.opacity(0.45))
            )
    }
}

extension View {
    func demoContentWidth() -> some View {
        frame(maxWidth: 560, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    func demoInputFieldStyle() -> some View {
        modifier(DemoFormFieldStyle())
    }

    @ViewBuilder
    func demoNavigationBarHidden() -> some View {
        if #available(iOS 16.0, *) {
            toolbar(.hidden, for: .navigationBar)
        } else {
            navigationBarHidden(true)
        }
    }
}
