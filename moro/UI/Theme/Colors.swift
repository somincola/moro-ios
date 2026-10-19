//
//  Colors.swift
//  moro
//
//  Defines Moro brand color palette with dark mode support.
//

import SwiftUI
import UIKit

struct MoroColors {
    // Color scheme for dynamic color switching
    let colorScheme: ColorScheme
    let accent: MoroAccentStyle
    let themeColor: MoroThemeColor
    let customThemeColor: UInt32
    let colorSchemeContrast: ColorSchemeContrast
    
    init(
        colorScheme: ColorScheme = .light, accent: MoroAccentStyle = .monochrome,
        themeColor: MoroThemeColor = .blue,
        customThemeColor: UInt32 = MoroThemeColor.defaultCustomRGB,
        colorSchemeContrast: ColorSchemeContrast = .standard
    ) {
        self.colorScheme = colorScheme
        self.accent = accent
        self.themeColor = themeColor
        self.customThemeColor = customThemeColor
        self.colorSchemeContrast = colorSchemeContrast
    }
    
    // MARK: - Primary Palette

    private struct PrimaryPalette {
        let p600: UInt32
        let p500: UInt32
        let p300: UInt32
        let p50: UInt32
    }

    private var primaryPalette: PrimaryPalette {
        switch colorScheme {
        case .light:
            return PrimaryPalette(p600: 0x111113, p500: 0x1C1C1E, p300: 0xB6B8BC, p50: 0xF3F4F6)
        case .dark:
            return PrimaryPalette(p600: 0xFFFFFF, p500: 0xF5F5F7, p300: 0x6B6D73, p50: 0x26272B)
        @unknown default:
            return PrimaryPalette(p600: 0x111113, p500: 0x1C1C1E, p300: 0xB6B8BC, p50: 0xF3F4F6)
        }
    }
    
    /// Primary 600 - Button pressed state / Active icon state
    var primary600: Color {
        Color(hex: primaryPalette.p600)
    }
    
    /// Primary 500 - Main brand color / Buttons / Links / Selected state
    var primary500: Color {
        Color(hex: primaryPalette.p500)
    }
    
    /// Primary 300 - Light background / Tag background
    var primary300: Color {
        Color(hex: primaryPalette.p300)
    }
    
    /// Primary 50 - Subtle background / Block background
    var primary50: Color {
        Color(hex: primaryPalette.p50)
    }
    
    // MARK: - Neutral Palette
    
    /// Text Primary - Main text (dark gray in light, white 87% in dark)
    var textPrimary: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0x111827)
        case .dark:
            // White 87% opacity
            return Color(red: 0.87, green: 0.87, blue: 0.87)
        @unknown default:
            return Color(hex: 0x111827)
        }
    }
    
    /// Text Secondary - Secondary text (time, account name)
    var textSecondary: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0x6B7280)
        case .dark:
            // White 60% opacity
            return Color(red: 0.60, green: 0.60, blue: 0.60)
        @unknown default:
            return Color(hex: 0x6B7280)
        }
    }
    
    /// Text Tertiary - Placeholder / Weak hints
    var textTertiary: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0x9AA0A6)
        case .dark:
            // White 38% opacity
            return Color(red: 0.38, green: 0.38, blue: 0.38)
        @unknown default:
            return Color(hex: 0x9AA0A6)
        }
    }
    
    /// Divider - Separator lines
    var divider: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0xF0F1F2)
        case .dark:
            // Darker divider for dark mode
            return Color(hex: 0x2A2C2E)
        @unknown default:
            return Color(hex: 0xF0F1F2)
        }
    }
    
    /// Border - Subtle borders (same as divider)
    var border: Color {
        return divider
    }
    
    /// Background - App background
    var background: Color {
        groupedBackground
    }

    /// Grouped Background - Light gray page/drawer background for grouped card surfaces.
    var groupedBackground: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0xF4F5F7)
        case .dark:
            return .black
        @unknown default:
            return Color.white
        }
    }
    
    /// Surface Subtle - Input box / Subtle area background
    var surfaceSubtle: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0xF8F9FA)
        case .dark:
            // Surface color from design system
            return Color(hex: 0x1A1C1E)
        @unknown default:
            return Color(hex: 0xFAFAFA)
        }
    }

    /// Skeleton - Loading placeholder blocks (avatar, text lines, profile header).
    /// One soft step above the page surface, so loading reads as quiet structure rather than
    /// content. Defined explicitly instead of relying on `.redacted(reason: .placeholder)`,
    /// whose primary-tinted fill turns near-white on the dark surface.
    var skeleton: Color {
        let isIncreased = colorSchemeContrast == .increased
        switch colorScheme {
        case .dark:
            return Color(hex: isIncreased ? 0x303236 : 0x24262A)
        default:
            return Color(hex: isIncreased ? 0xDCDEE1 : 0xEBECEE)
        }
    }

    /// Use the system's darker base card color consistently inside the settings sheet.
    var groupedSurface: Color {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            traits.userInterfaceLevel = .base
            traits.accessibilityContrast = colorSchemeContrast == .increased ? .high : .normal
        }
        return Color(uiColor: UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits))
    }

    /// Surface Base - Primary page surface for cards/containers
    var surfaceBase: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0xFFFFFF)
        case .dark:
            return Color(hex: 0x16181A)
        @unknown default:
            return Color(hex: 0xFFFFFF)
        }
    }

    /// Surface Elevated - Slightly raised surface
    var surfaceElevated: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0xFCFCFC)
        case .dark:
            return Color(hex: 0x1D1F22)
        @unknown default:
            return Color(hex: 0xFCFCFC)
        }
    }

    /// Immersive Background - Media and other distraction-free full-screen content.
    var immersiveBackground: Color {
        .black
    }

    /// Border Subtle - Lighter border than divider for grouped cards
    var borderSubtle: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0xEFEFEF)
        case .dark:
            return Color(hex: 0x2F3236)
        @unknown default:
            return Color(hex: 0xEFEFEF)
        }
    }

    /// Text Muted - Lower emphasis text in quiet sections
    var textMuted: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0x8A919A)
        case .dark:
            return Color(red: 0.50, green: 0.50, blue: 0.50)
        @unknown default:
            return Color(hex: 0x8A919A)
        }
    }

    /// Shared accent for content links, enabled settings switches and inbox badges.
    var themeTint: Color { Color(hex: themeTintHex) }

    var contentLink: Color { themeTint }

    var themeTintForeground: Color {
        let luminance = Self.luminance(themeTintHex)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? .black : .white
    }

    private var themeTintHex: UInt32 {
        let increased = colorSchemeContrast == .increased
        let shades: (light: UInt32, dark: UInt32)
        switch themeColor {
        case .blue:
            shades = increased ? (0x004C99, 0x7DBAFF) : (0x0066CC, 0x4DA3FF)
        case .yellow:
            shades = increased ? (0x6B4B00, 0xFFE080) : (0x8A6400, 0xF2C94C)
        case .pink:
            shades = increased ? (0x9C1048, 0xFF98C1) : (0xC2185B, 0xFF70AB)
        case .purple:
            shades = increased ? (0x51318F, 0xCDBAFF) : (0x6F42C1, 0xB69CFF)
        case .orange:
            shades = increased ? (0x853B00, 0xFFC18F) : (0xB45100, 0xFFAA66)
        case .green:
            shades = increased ? (0x005C44, 0x8AE8C6) : (0x007F5F, 0x53D6A4)
        case .custom:
            return accessibleCustomTint
        }
        return colorScheme == .dark ? shades.dark : shades.light
    }

    private var accessibleCustomTint: UInt32 {
        let original = customThemeColor & 0xFFFFFF
        let backgrounds: [UInt32] = colorScheme == .dark
            ? [0x16181A, 0x1A1C1E, 0x1D1F22, 0x000000]
            : [0xFFFFFF, 0xF8F9FA, 0xFCFCFC, 0xF4F5F7]
        let minimumContrast = colorSchemeContrast == .increased ? 7.0 : 4.5
        func isReadable(_ color: UInt32) -> Bool {
            let foreground = Self.luminance(color)
            return backgrounds.allSatisfy { background in
                let luminance = Self.luminance(background)
                return (max(foreground, luminance) + 0.05) / (min(foreground, luminance) + 0.05) >= minimumContrast
            }
        }
        guard !isReadable(original) else { return original }

        // Keep the chosen RGB value; adjust only its rendered shade for the active surfaces.
        let destination = colorScheme == .dark ? 255.0 : 0.0
        func shade(_ amount: Double) -> UInt32 {
            var hex: UInt32 = 0
            for shift in [16, 8, 0] {
                let component = Double((original >> shift) & 0xFF)
                hex |= UInt32((component + (destination - component) * amount).rounded()) << shift
            }
            return hex
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<12 {
            let middle = (lower + upper) / 2
            if isReadable(shade(middle)) {
                upper = middle
            } else {
                lower = middle
            }
        }
        return shade(upper)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func linear(_ shift: Int) -> Double {
            let component = Double((hex >> shift) & 0xFF) / 255
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /// Unread indicators retain their status color independently of content preferences.
    var unreadIndicator: Color {
        Color(hex: colorScheme == .dark ? 0x4DA3FF : 0x0A84FF)
    }
    
    // MARK: - Semantic Colors
    
    /// Success - Success state
    var success: Color {
        // Semantic colors remain the same in both modes
        return Color(hex: 0x4CAF50)
    }

    /// Boost Active - Selected boost/reblog action in post chrome.
    var boostActive: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0x34C759)
        case .dark:
            return Color(hex: 0x30D158)
        @unknown default:
            return Color(hex: 0x34C759)
        }
    }

    /// Bookmark Active - Selected bookmark action in post chrome.
    var bookmarkActive: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0x4A90E2)
        case .dark:
            return Color(hex: 0x6AAEFF)
        @unknown default:
            return Color(hex: 0x4A90E2)
        }
    }
    
    /// Error - Error state
    var error: Color {
        return Color(hex: 0xE5484D)
    }
    
    /// Warning - Warning state
    var warning: Color {
        return Color(hex: 0xF4B400)
    }

    /// Foreground color intended for content rendered on top of primary fills.
    var primaryForeground: Color {
        switch (accent, colorScheme) {
        case (.monochrome, .dark):
            return .black
        default:
            return .white
        }
    }
}

// MARK: - Color Extensions

extension Color {
    /// Initialize Color from hex UInt32 value
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    /// Initialize Color from hex String (e.g., "A98BE8" or "#A98BE8")
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let r, g, b: UInt64

        switch sanitized.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 1)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
