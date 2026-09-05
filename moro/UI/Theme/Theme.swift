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

struct MoroTheme {
    let colorScheme: ColorScheme
    let accent: MoroAccentStyle
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
        fontScale: CGFloat = 1.0,
        dynamicTypeSize: DynamicTypeSize = .large
    ) {
        self.colorScheme = colorScheme
        self.accent = accent
        self.colors = MoroColors(colorScheme: colorScheme, accent: accent)
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
