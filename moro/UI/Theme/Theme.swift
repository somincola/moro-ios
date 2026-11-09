//
//  Theme.swift
//  moro
//
//  Convenience accessors for Moro design system.
//

import SwiftUI
import UIKit

enum MoroAccentStyle: String {
    case monochrome
}

enum MoroThemeColor: String, CaseIterable {
    case blue, yellow, pink, purple, orange, green, custom

    static let defaultCustomRGB: UInt32 = 0x0052A3

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

enum MoroPostFontSize: Int, CaseIterable {
    case small = 14, standard = 16, large = 18, extraLarge = 20

    var title: String {
        switch self {
        case .small: MoroL10n.Display.fontSmall
        case .standard: MoroL10n.Display.fontStandard
        case .large: MoroL10n.Display.fontLarge
        case .extraLarge: MoroL10n.Display.fontExtraLarge
        }
    }
}

struct MoroTheme {
    let colorScheme: ColorScheme
    let colorSchemeContrast: ColorSchemeContrast
    let accent: MoroAccentStyle
    let themeColor: MoroThemeColor
    let customThemeColor: UInt32
    let postFontSize: MoroPostFontSize
    let colors: MoroColors
    let spacing = MoroSpacing()
    let typography = MoroTypography()
    let dynamicTypeSize: DynamicTypeSize

    init(
        colorScheme: ColorScheme = .light,
        accent: MoroAccentStyle = .monochrome,
        themeColor: MoroThemeColor = .blue,
        customThemeColor: UInt32 = MoroThemeColor.defaultCustomRGB,
        postFontSize: MoroPostFontSize = .standard,
        colorSchemeContrast: ColorSchemeContrast = .standard,
        dynamicTypeSize: DynamicTypeSize = .large
    ) {
        self.colorScheme = colorScheme
        self.colorSchemeContrast = colorSchemeContrast
        self.accent = accent
        self.themeColor = themeColor
        self.customThemeColor = customThemeColor
        self.postFontSize = postFontSize
        self.colors = MoroColors(
            colorScheme: colorScheme, accent: accent,
            themeColor: themeColor, customThemeColor: customThemeColor,
            colorSchemeContrast: colorSchemeContrast
        )
        self.dynamicTypeSize = dynamicTypeSize
    }

    // Post reading sizes use the body curve, including the focused post's +2pt.
    @MainActor
    func postUIFont(for size: MoroPostFontSize? = nil, sizeAdjustment: CGFloat = 0, weight: UIFont.Weight = .regular) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: CGFloat((size ?? postFontSize).rawValue) + sizeAdjustment, weight: weight),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
        )
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
