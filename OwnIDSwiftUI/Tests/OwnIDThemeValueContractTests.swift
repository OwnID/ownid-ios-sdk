import SwiftUI
import Testing

@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-040
struct OwnIDThemeValueContractTests {
    @Test func `OwnID colors and theme preserve explicit values and Hashable semantics`() {
        let colors = Self.explicitColors(primary: .red)
        let sameColors = Self.explicitColors(primary: .red)
        let changedColors = Self.explicitColors(primary: .black)

        #expect(colors == sameColors)
        #expect(colors != changedColors)
        #expect(Set([colors, sameColors, changedColors]).count == 2)

        let theme = OwnIDTheme(colors: colors)
        let sameTheme = OwnIDTheme(colors: sameColors)
        let changedTheme = OwnIDTheme(colors: changedColors)

        #expect(theme.colors == colors)
        #expect(theme == sameTheme)
        #expect(theme != changedTheme)
        #expect(Set([theme, sameTheme, changedTheme]).count == 2)
    }

    @Test func `OwnID source-owned light and dark defaults remain stable`() {
        let lightDefaults = OwnIDColors.sdkDefault(for: .light)
        let darkDefaults = OwnIDColors.sdkDefault(for: .dark)

        #expect(lightDefaults == Self.expectedLightDefaults)
        #expect(OwnIDTheme.sdkDefault(for: .light) == OwnIDTheme(colors: Self.expectedLightDefaults))
        #expect(darkDefaults == Self.expectedDarkDefaults)
        #expect(OwnIDTheme.sdkDefault(for: .dark) == OwnIDTheme(colors: Self.expectedDarkDefaults))
        #expect(lightDefaults != darkDefaults)
    }

    @Test func `OwnID captured values keep source-owned defaults for unmapped tokens`() {
        let capturedLight = OwnIDTheme.capture(colorScheme: .light, primary: .red, onPrimary: .black)
        let capturedDark = OwnIDTheme.capture(colorScheme: .dark, primary: .green, onPrimary: .white)

        #expect(capturedLight.colors.primary == .red)
        #expect(capturedLight.colors.onPrimary == .black)
        #expect(capturedLight.colors.checkmarkButtonBackground == Self.expectedLightDefaults.checkmarkButtonBackground)
        #expect(capturedLight.colors.checkmarkButton == Self.expectedLightDefaults.checkmarkButton)

        #expect(capturedDark.colors.primary == .green)
        #expect(capturedDark.colors.onPrimary == .white)
        #expect(capturedDark.colors.checkmarkButtonBackground == Self.expectedDarkDefaults.checkmarkButtonBackground)
        #expect(capturedDark.colors.checkmarkButton == Self.expectedDarkDefaults.checkmarkButton)
    }

    private static let expectedLightDefaults = OwnIDColors(
        primary: Color(hex: "#1A73E8"),
        onPrimary: .white,
        error: Color(hex: "#B3261E"),
        surface: .white,
        onSurface: .black,
        onSurfaceVariant: Color(hex: "#757575"),
        fieldBackground: .clear,
        progress: Color(hex: "#858585"),
        progressTrack: Color(hex: "#858585").opacity(0.3),
        iconButtonBackground: Color(hex: "#FFFFFF"),
        iconButtonBackgroundDisabled: Color(hex: "#FFFFFF"),
        iconButtonBorder: Color(hex: "#D0D0D0"),
        checkmarkButtonBackground: Color(hex: "#36A41D"),
        checkmarkButton: Color(hex: "#FFFFFF")
    )

    private static let expectedDarkDefaults = OwnIDColors(
        primary: Color(hex: "#82B1FF"),
        onPrimary: .black,
        error: Color(hex: "#F2B8B5"),
        surface: Color(hex: "#2A2831"),
        onSurface: .white,
        onSurfaceVariant: Color(hex: "#CAC4D0"),
        fieldBackground: .clear,
        progress: Color(hex: "#ADADAD"),
        progressTrack: Color(hex: "#DFDFDF"),
        iconButtonBackground: Color(hex: "#2A3743"),
        iconButtonBackgroundDisabled: Color(hex: "#2A3743"),
        iconButtonBorder: Color(hex: "#2A3743"),
        checkmarkButtonBackground: Color(hex: "#66BB6A"),
        checkmarkButton: Color(hex: "#000000")
    )

    private static func explicitColors(primary: Color) -> OwnIDColors {
        OwnIDColors(
            primary: primary,
            onPrimary: .white,
            error: .orange,
            surface: .black,
            onSurface: .green,
            onSurfaceVariant: .blue,
            fieldBackground: .gray,
            progress: .yellow,
            progressTrack: .pink,
            iconButtonBackground: .purple,
            iconButtonBackgroundDisabled: .gray,
            iconButtonBorder: .blue,
            checkmarkButtonBackground: .green,
            checkmarkButton: .red
        )
    }
}
