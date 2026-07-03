import OwnIDSwiftUI
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct Palette {
    let background: Color
    let cardBackground: Color
    let border: Color
    let primary: Color
    let onPrimary: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let fieldBackground: Color
}

enum Theme {
    static func palette(for colorScheme: ColorScheme) -> Palette {
        switch colorScheme {
        case .dark:
            return Palette(
                background: Color(hex: 0x0C0C12),
                cardBackground: Color(hex: 0x16171F),
                border: Color(hex: 0x2B2D39),
                primary: Color(hex: 0x75BAB3),
                onPrimary: .black,
                onSurface: Color(hex: 0xE7EBF2),
                onSurfaceVariant: Color(hex: 0xE7EBF2, alpha: 0.7),
                fieldBackground: Color(hex: 0x12141B)
            )
        default:
            return Palette(
                background: Color(hex: 0xF3F0E6),
                cardBackground: .white,
                border: Color(hex: 0xDCE2EB),
                primary: Color(hex: 0x2F6F6A),
                onPrimary: .white,
                onSurface: .black,
                onSurfaceVariant: Color(hex: 0x8E9AAF),
                fieldBackground: .white
            )
        }
    }

    static func ownIDWidgetTheme(for colorScheme: ColorScheme) -> OwnIDTheme {
        let palette = palette(for: colorScheme)
        var theme = OwnIDTheme.capture(colorScheme: colorScheme, primary: palette.primary, onPrimary: palette.onPrimary)
        theme.colors.fieldBackground = palette.fieldBackground
        theme.colors.iconButtonBackground = palette.fieldBackground
        theme.colors.iconButtonBackgroundDisabled = palette.fieldBackground
        theme.colors.iconButtonBorder = palette.border
        return theme
    }
}
