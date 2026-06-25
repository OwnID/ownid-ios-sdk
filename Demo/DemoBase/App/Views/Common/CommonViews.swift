import Combine
import SwiftUI

struct DemoHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .regular))
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.onSurface)
            }

            Text(title)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            Image("OwnIDLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 34)
                .foregroundStyle(palette.onSurface)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let palette = Theme.palette(for: colorScheme)

        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(12)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DemoFormFieldStyle: ViewModifier {
    static let height: CGFloat = 44

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = Theme.palette(for: colorScheme)

        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.fieldBackground)
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
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
