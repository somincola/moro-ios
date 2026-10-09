//
//  Theme.swift
//  moro
//
//  Convenience accessors for Moro design system.
//

import SwiftUI

enum MoroAccentStyle: String {
    case monochrome
}

enum MoroThemeColor: String, CaseIterable {
    case blue, yellow, pink, purple, orange, green, custom

    static let defaultCustomRGB: UInt32 = 0x0066CC

    var title: String {
        switch self {
        case .blue: MoroL10n.Display.blue
        case .yellow: MoroL10n.Display.yellow
        case .pink: MoroL10n.Display.pink
        case .purple: MoroL10n.Display.purple
        case .orange: MoroL10n.Display.orange
        case .green: MoroL10n.Display.green
        case .custom: MoroL10n.Display.customColor
        }
    }
}

struct MoroTheme {
    let colorScheme: ColorScheme
    let colorSchemeContrast: ColorSchemeContrast
    let accent: MoroAccentStyle
    let themeColor: MoroThemeColor
    let customThemeColor: UInt32
    let colors: MoroColors
    let spacing = MoroSpacing()
    let typography: MoroTypography
    /// The in-app font-scale factor baked into `typography`, exposed for
    /// fixed-point helpers like `.moroScaledFont` so they can read it from
    /// the environment instead of observing AppSettings per call site.
    let fontScale: CGFloat
    let dynamicTypeSize: DynamicTypeSize

    init(
        colorScheme: ColorScheme = .light,
        accent: MoroAccentStyle = .monochrome,
        themeColor: MoroThemeColor = .blue,
        customThemeColor: UInt32 = MoroThemeColor.defaultCustomRGB,
        colorSchemeContrast: ColorSchemeContrast = .standard,
        fontScale: CGFloat = 1.0,
        dynamicTypeSize: DynamicTypeSize = .large
    ) {
        self.colorScheme = colorScheme
        self.colorSchemeContrast = colorSchemeContrast
        self.accent = accent
        self.themeColor = themeColor
        self.customThemeColor = customThemeColor
        self.colors = MoroColors(
            colorScheme: colorScheme, accent: accent,
            themeColor: themeColor, customThemeColor: customThemeColor,
            colorSchemeContrast: colorSchemeContrast
        )
        self.typography = MoroTypography(fontScale: fontScale, dynamicTypeSize: dynamicTypeSize)
        self.fontScale = fontScale
        self.dynamicTypeSize = dynamicTypeSize
    }
}

private struct MoroThemeKey: EnvironmentKey {
    static let defaultValue = MoroTheme()
}

extension EnvironmentValues {
    var moroTheme: MoroTheme {
        get { self[MoroThemeKey.self] }
        set { self[MoroThemeKey.self] = newValue }
    }
}

extension View {
    func moroTheme(_ theme: MoroTheme) -> some View {
        environment(\.moroTheme, theme)
    }
}
