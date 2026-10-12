//
//  MoroUIKitThemePalette.swift
//  moro
//
//  Semantic UIKit projection of MoroTheme for UIKit-hosted feature surfaces.
//

#if os(iOS)
    import SwiftUI
    import UIKit

    struct MoroUIKitThemePalette {
        let colorScheme: ColorScheme
        let colorSchemeContrast: ColorSchemeContrast
        let accent: MoroAccentStyle
        let themeColor: MoroThemeColor
        let customThemeColor: UInt32
        let postFontSize: MoroPostFontSize
        let dynamicTypeSize: DynamicTypeSize

        let canvasBackground: UIColor
        let groupedBackground: UIColor
        let surfaceBase: UIColor
        let surfaceSubtle: UIColor
        let surfaceElevated: UIColor
        let textPrimary: UIColor
        let textSecondary: UIColor
        let textTertiary: UIColor
        let divider: UIColor
        let borderSubtle: UIColor
        let primary: UIColor
        let primarySubtle: UIColor
        let contentLink: UIColor

        init(theme: MoroTheme) {
            colorScheme = theme.colorScheme
            colorSchemeContrast = theme.colorSchemeContrast
            accent = theme.accent
            themeColor = theme.themeColor
            customThemeColor = theme.customThemeColor
            postFontSize = theme.postFontSize
            dynamicTypeSize = theme.dynamicTypeSize
            canvasBackground = UIColor(theme.colors.surfaceBase)
            groupedBackground = UIColor(theme.colors.groupedBackground)
            surfaceBase = UIColor(theme.colors.surfaceBase)
            surfaceSubtle = UIColor(theme.colors.surfaceSubtle)
            surfaceElevated = UIColor(theme.colors.surfaceElevated)
            textPrimary = UIColor(theme.colors.textPrimary)
            textSecondary = UIColor(theme.colors.textSecondary)
            textTertiary = UIColor(theme.colors.textTertiary)
            divider = UIColor(theme.colors.divider)
            borderSubtle = UIColor(theme.colors.borderSubtle)
            primary = UIColor(theme.colors.primary500)
            primarySubtle = UIColor(theme.colors.primary50)
            contentLink = UIColor(theme.colors.contentLink)
        }

        var interfaceStyle: UIUserInterfaceStyle {
            colorScheme == .dark ? .dark : .light
        }

        func font(
            forTextStyle textStyle: UIFont.TextStyle,
            weight: UIFont.Weight = .regular
        ) -> UIFont {
            let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
            let preferredPointSize = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits).pointSize
            return UIFont.systemFont(
                ofSize: preferredPointSize,
                weight: weight
            )
        }

        func matches(_ theme: MoroTheme) -> Bool {
            colorScheme == theme.colorScheme
                && colorSchemeContrast == theme.colorSchemeContrast
                && accent == theme.accent
                && themeColor == theme.themeColor
                && customThemeColor == theme.customThemeColor
                && postFontSize == theme.postFontSize
                && dynamicTypeSize == theme.dynamicTypeSize
        }
    }

    extension MoroTheme {
        var uiKitPalette: MoroUIKitThemePalette {
            MoroUIKitThemePalette(theme: self)
        }
    }
#endif
