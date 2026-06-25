import SwiftUI

/// Semantic color tokens used by OwnID SwiftUI views.
///
/// Provide a complete palette when you want OwnID UI to match your app theme. Tokens are semantic rather than tied to
/// one call site, so the same palette can be used across OwnID surfaces. If you only need to override part of
/// the palette, capture a theme with ``OwnIDTheme/capture(colorScheme:)`` and mutate selected fields in
/// ``View/ownIDTheme(instanceName:customize:)`` or before passing a theme to a view.
///
/// OwnID uses the supplied values as-is. When overriding paired colors such as ``primary``/``onPrimary`` or
/// ``surface``/``onSurface``, provide foreground colors that remain readable on the matching background.
public struct OwnIDColors: Sendable, Equatable, Hashable {
    public var primary: Color
    public var onPrimary: Color
    public var error: Color
    public var surface: Color
    public var onSurface: Color
    public var onSurfaceVariant: Color
    public var fieldBackground: Color
    public var progress: Color
    public var progressTrack: Color
    public var iconButtonBackground: Color
    public var iconButtonBackgroundDisabled: Color
    public var iconButtonBorder: Color
    public var checkmarkButtonBackground: Color
    public var checkmarkButton: Color

    /// Creates a complete OwnID color palette.
    ///
    /// All color values are required. To use SDK defaults for unspecified roles, start from
    /// ``OwnIDTheme/capture(colorScheme:)`` and override selected properties instead of constructing this type
    /// directly.
    public init(
        primary: Color,
        onPrimary: Color,
        error: Color,
        surface: Color,
        onSurface: Color,
        onSurfaceVariant: Color,
        fieldBackground: Color,
        progress: Color,
        progressTrack: Color,
        iconButtonBackground: Color,
        iconButtonBackgroundDisabled: Color,
        iconButtonBorder: Color,
        checkmarkButtonBackground: Color,
        checkmarkButton: Color
    ) {
        self.primary = primary
        self.onPrimary = onPrimary
        self.error = error
        self.surface = surface
        self.onSurface = onSurface
        self.onSurfaceVariant = onSurfaceVariant
        self.fieldBackground = fieldBackground
        self.progress = progress
        self.progressTrack = progressTrack
        self.iconButtonBackground = iconButtonBackground
        self.iconButtonBackgroundDisabled = iconButtonBackgroundDisabled
        self.iconButtonBorder = iconButtonBorder
        self.checkmarkButtonBackground = checkmarkButtonBackground
        self.checkmarkButton = checkmarkButton
    }
}

extension OwnIDColors {
    internal static func sdkDefault(for colorScheme: ColorScheme) -> OwnIDColors {
        switch colorScheme {
        case .dark:
            return OwnIDColors(
                primary: Color(hex: "#82B1FF"),
                onPrimary: .black,
                error: Color(hex: "#F2B8B5"),
                surface: Color(hex: "#2A2831"),
                onSurface: .white,
                onSurfaceVariant: Color(hex: "#CAC4D0"),
                fieldBackground: .clear,
                progress: Color(hex: "#ADADAD"),
                progressTrack: Color(hex: "#DFDFDF"),
                iconButtonBackground: Color(Self.darkIconButtonBackground),
                iconButtonBackgroundDisabled: Color(Self.darkIconButtonBackground),
                iconButtonBorder: Color(Self.darkIconButtonBorder),
                checkmarkButtonBackground: Color(Self.darkCheckmarkButtonBackground),
                checkmarkButton: Color(Self.darkCheckmarkButton)
            )
        default:
            return OwnIDColors(
                primary: Color(hex: "#1A73E8"),
                onPrimary: .white,
                error: Color(hex: "#B3261E"),
                surface: .white,
                onSurface: .black,
                onSurfaceVariant: Color(hex: "#757575"),
                fieldBackground: .clear,
                progress: Color(hex: "#858585"),
                progressTrack: Color(hex: "#858585").opacity(0.3),
                iconButtonBackground: Color(Self.lightIconButtonBackground),
                iconButtonBackgroundDisabled: Color(Self.lightIconButtonBackground),
                iconButtonBorder: Color(Self.lightIconButtonBorder),
                checkmarkButtonBackground: Color(Self.lightCheckmarkButtonBackground),
                checkmarkButton: Color(Self.lightCheckmarkButton)
            )
        }
    }

    internal static func capture(colorScheme: ColorScheme) -> OwnIDColors {
        let defaults = sdkDefault(for: colorScheme)
        return capture(colorScheme: colorScheme, primary: .accentColor, onPrimary: defaults.onPrimary)
    }

    internal static func capture(colorScheme: ColorScheme, primary: Color, onPrimary: Color) -> OwnIDColors {
        let defaults = sdkDefault(for: colorScheme)
        let controlBackground = Color(uiColorCompat: .secondarySystemBackground)

        return OwnIDColors(
            primary: primary,
            onPrimary: onPrimary,
            error: Color(uiColorCompat: .systemRed),
            surface: Color(uiColorCompat: .systemBackground),
            onSurface: .primary,
            onSurfaceVariant: .secondary,
            fieldBackground: controlBackground,
            progress: .secondary,
            progressTrack: .secondary.opacity(0.3),
            iconButtonBackground: controlBackground,
            iconButtonBackgroundDisabled: controlBackground,
            iconButtonBorder: Color(uiColorCompat: .separator),
            checkmarkButtonBackground: defaults.checkmarkButtonBackground,
            checkmarkButton: defaults.checkmarkButton
        )
    }

    private static let lightIconButtonBackground = UIColor(hex: "#FFFFFF")
    private static let lightIconButtonBorder = UIColor(hex: "#D0D0D0")
    private static let lightCheckmarkButton = UIColor(hex: "#FFFFFF")
    private static let lightCheckmarkButtonBackground = UIColor(hex: "#36A41D")

    private static let darkIconButtonBackground = UIColor(hex: "#2A3743")
    private static let darkIconButtonBorder = UIColor(hex: "#2A3743")
    private static let darkCheckmarkButton = UIColor(hex: "#000000")
    private static let darkCheckmarkButtonBackground = UIColor(hex: "#66BB6A")
}

extension UIColor {
    internal convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

extension Color {
    internal init(hex: String) {
        self.init(uiColorCompat: UIColor(hex: hex))
    }
}
