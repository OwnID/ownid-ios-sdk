import SwiftUI

/// Color configuration for ``OwnIDCheckmarkView``.
///
/// The default values come from ``OwnIDColors`` through ``OwnIDCheckmarkDefaults/colors(colors:)``.
public struct OwnIDCheckmarkColors {
    internal let color: Color
    internal let backgroundColor: Color

    /// Creates a color set for the checkmark badge.
    public init(color: Color, backgroundColor: Color) {
        self.color = color
        self.backgroundColor = backgroundColor
    }
}

/// Default icon and color values for ``OwnIDCheckmarkView``.
public enum OwnIDCheckmarkDefaults {

    /// Default checkmark icon.
    public static let icon = Image(systemName: "checkmark")

    /// Returns default checkmark colors derived from the provided OwnID theme colors.
    public static func colors(colors: OwnIDColors) -> OwnIDCheckmarkColors {
        OwnIDCheckmarkColors(color: colors.checkmarkButton, backgroundColor: colors.checkmarkButtonBackground)
    }
}

/// Displays the standard OwnID completion badge.
///
/// The badge is hidden from accessibility by default and should not be the only place where a completed state is
/// communicated. Add parent accessibility semantics or visible status text when completion needs to be announced.
/// Size is caller-controlled with layout modifiers; the badge keeps a square aspect ratio.
public struct OwnIDCheckmarkView: View {
    @Environment(\.ownIDTheme) private var ownIDTheme
    @Environment(\.colorScheme) private var colorScheme

    private let icon: Image
    private let customColors: OwnIDCheckmarkColors?

    /// Creates a completion badge view.
    ///
    /// - Parameters:
    ///   - icon: Checkmark icon. Defaults to ``OwnIDCheckmarkDefaults/icon``.
    ///   - colors: Optional custom colors. When `nil`, defaults are derived from the current OwnID theme.
    public init(
        icon: Image = OwnIDCheckmarkDefaults.icon,
        colors: OwnIDCheckmarkColors? = nil
    ) {
        self.icon = icon
        self.customColors = colors
    }

    private var resolvedColors: OwnIDCheckmarkColors {
        customColors ?? OwnIDCheckmarkDefaults.colors(colors: (ownIDTheme ?? OwnIDTheme.capture(colorScheme: colorScheme)).colors)
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(resolvedColors.backgroundColor)

            icon
                .resizable()
                .scaledToFit()
                .padding(.all, 4)
                .foregroundColor(resolvedColors.color)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHiddenCompat(true)
    }
}
