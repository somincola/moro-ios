//
//  Colors.swift
//  moro
//
//  Defines Moro brand color palette with dark mode support.
//

import SwiftUI

struct MoroColors {
    // Color scheme for dynamic color switching
    let colorScheme: ColorScheme
    let accent: MoroAccentStyle
    
    init(colorScheme: ColorScheme = .light, accent: MoroAccentStyle = .monochrome) {
        self.colorScheme = colorScheme
        self.accent = accent
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

    /// Content Link - Mentions, hashtags and inline links rendered inside post/account rich text.
    var contentLink: Color {
        switch colorScheme {
        case .light:
            return Color(hex: 0x0A84FF)
        case .dark:
            return Color(hex: 0x4DA3FF)
        @unknown default:
            return Color(hex: 0x0A84FF)
        }
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
