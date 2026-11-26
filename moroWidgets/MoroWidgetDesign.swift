//
//  MoroWidgetDesign.swift
//  moroWidgets
//
//  Adaptive Monochrome Editorial visual language for Moro Home & Lock Screen widgets.
//  Echoes Moro's warm paper / obsidian ink aesthetic, dynamic user theme accent,
//  iOS 18+ Tinted Home Screen rendering, and minimalist line-art elephant mark.
//

import SwiftUI
import UIKit
import WidgetKit

// MARK: - Color Hex Helper

extension Color {
    init(moroHex hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Adaptive Editorial Palette

struct MoroWidgetPalette {
    let colorScheme: ColorScheme
    let renderingMode: WidgetRenderingMode
    let accent: MoroWidgetAccent

    var isFullColor: Bool { renderingMode == .fullColor }
    var isDark: Bool { colorScheme == .dark }

    // Canvas
    var canvasTop: Color {
        isDark ? Color(moroHex: 0x16171B) : Color(moroHex: 0xFAF9F6)
    }

    var canvasBottom: Color {
        isDark ? Color(moroHex: 0x0C0D10) : Color(moroHex: 0xF1F0EB)
    }

    var canvasSheen: Color {
        isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.85)
    }

    var canvasAmbientStroke: Color {
        isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    // Surfaces
    var tileSurface: Color {
        guard isFullColor else { return Color.white.opacity(0.11) }
        return isDark ? Color(moroHex: 0x1F2127) : Color(moroHex: 0xFFFFFF)
    }

    var tileBorder: Color {
        guard isFullColor else { return Color.white.opacity(0.20) }
        return isDark ? Color.white.opacity(0.095) : Color.black.opacity(0.075)
    }

    var subtleSurface: Color {
        guard isFullColor else { return Color.white.opacity(0.08) }
        return isDark ? Color(moroHex: 0x1B1D22) : Color(moroHex: 0xEFECE5)
    }

    var divider: Color {
        guard isFullColor else { return Color.white.opacity(0.18) }
        return isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    // Primary Inverted Action (Moro Monochrome Signature)
    var primaryTileFill: Color {
        guard isFullColor else { return Color.white.opacity(0.24) }
        return isDark ? Color(moroHex: 0xF4F4F6) : Color(moroHex: 0x161618)
    }

    var primaryTileBorder: Color {
        guard isFullColor else { return Color.white.opacity(0.32) }
        return isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.12)
    }

    var primaryTileForeground: Color {
        guard isFullColor else { return .primary }
        return isDark ? Color(moroHex: 0x111214) : Color.white
    }

    var primaryTileSecondaryForeground: Color {
        guard isFullColor else { return .secondary }
        return isDark ? Color(moroHex: 0x111214).opacity(0.62) : Color.white.opacity(0.68)
    }

    // Ink Typography
    var inkPrimary: Color {
        guard isFullColor else { return .primary }
        return isDark ? Color(moroHex: 0xF3F4F6) : Color(moroHex: 0x141518)
    }

    var inkSecondary: Color {
        guard isFullColor else { return .secondary }
        return isDark ? Color(moroHex: 0x9A9DA6) : Color(moroHex: 0x666B74)
    }

    var inkTertiary: Color {
        guard isFullColor else { return .secondary.opacity(0.75) }
        return isDark ? Color(moroHex: 0x6D707A) : Color(moroHex: 0x90959E)
    }

    // Dynamic User Accent (Synced from AppSettings.themeColor)
    var accentTint: Color {
        guard isFullColor else { return .primary }
        return Color(moroHex: accent.resolvedHex(isDarkMode: isDark))
    }

    var accentForeground: Color {
        guard isFullColor else { return Color.black }
        return accent.prefersDarkForeground(isDarkMode: isDark) ? Color(moroHex: 0x111214) : Color.white
    }

    var accentSubtleFill: Color {
        guard isFullColor else { return Color.white.opacity(0.14) }
        return accentTint.opacity(isDark ? 0.20 : 0.12)
    }

    // Shadow
    var tileShadowColor: Color {
        guard isFullColor else { return .clear }
        return isDark ? Color.black.opacity(0.26) : Color.black.opacity(0.05)
    }

}

// MARK: - Editorial Canvas Background

struct MoroWidgetSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let accent: MoroWidgetAccent

    init(accent: MoroWidgetAccent = .default) {
        self.accent = accent
    }

    var body: some View {
        let palette = MoroWidgetPalette(
            colorScheme: colorScheme,
            renderingMode: renderingMode,
            accent: accent
        )

        if palette.isFullColor {
            ZStack {
                LinearGradient(
                    colors: [palette.canvasTop, palette.canvasBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Soft architectural light sheen in top-trailing quadrant
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [palette.canvasSheen, Color.clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)
                    .offset(x: 92, y: -74)

                // Subtle editorial geometric arc
                Circle()
                    .stroke(palette.canvasAmbientStroke, lineWidth: 0.75)
                    .frame(width: 176, height: 176)
                    .offset(x: -90, y: 92)
            }
        } else {
            Color.clear
        }
    }
}

// MARK: - Minimalist Moro Elephant Line-Art Emblem

/// Echoes Moro's in-app minimalist monochrome line-art elephant mascot (`MoroMascotGeometry`).
struct MoroWidgetElephantMark: View {
    enum Expression {
        case calm
        case resting
    }

    var expression: Expression = .calm
    var size: CGFloat = 22
    var primaryColor: Color
    var secondaryColor: Color? = nil

    var body: some View {
        let lineWidth = max(1.15, min(2.2, size * 0.056))
        let primaryStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let secondaryStyle = StrokeStyle(
            lineWidth: max(0.95, lineWidth * 0.84),
            lineCap: .round,
            lineJoin: .round
        )
        let paths = Self.paths(for: expression, in: CGSize(width: size, height: size))

        ZStack {
            paths.secondary
                .stroke(secondaryColor ?? primaryColor.opacity(0.55), style: secondaryStyle)
            paths.primary
                .stroke(primaryColor, style: primaryStyle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static func paths(
        for expression: Expression,
        in size: CGSize
    ) -> (primary: Path, secondary: Path) {
        let side = min(size.width, size.height)
        let originX = (size.width - side) * 0.5
        let originY = (size.height - side) * 0.5
        let scale = side / 100.0

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var primary = Path()
        var secondary = Path()

        // Back / right ear peeking behind forehead
        secondary.move(to: pt(64.0, 35.5))
        secondary.addQuadCurve(to: pt(78.5, 32.0), control: pt(71.5, 30.5))
        secondary.addCurve(to: pt(75.0, 48.5), control1: pt(80.2, 37.5), control2: pt(78.2, 45.0))
        secondary.addQuadCurve(to: pt(70.5, 50.8), control: pt(73.0, 50.0))

        // Left wing-ear
        primary.move(to: pt(39.0, 35.0))
        primary.addCurve(to: pt(17.5, 37.5), control1: pt(31.5, 26.5), control2: pt(20.5, 29.0))
        primary.addCurve(to: pt(24.5, 65.5), control1: pt(13.0, 46.5), control2: pt(16.8, 59.0))
        primary.addCurve(to: pt(40.5, 61.5), control1: pt(29.8, 70.2), control2: pt(36.2, 67.8))

        // Crown, forehead, and signature playful upturned trunk
        primary.move(to: pt(39.0, 35.0))
        primary.addCurve(to: pt(69.0, 43.5), control1: pt(47.0, 23.5), control2: pt(64.5, 25.5))
        primary.addCurve(to: pt(73.5, 61.5), control1: pt(72.0, 50.5), control2: pt(71.0, 56.5))
        primary.addCurve(to: pt(84.0, 56.5), control1: pt(77.0, 65.8), control2: pt(84.0, 62.8))
        primary.addQuadCurve(to: pt(83.8, 63.5), control: pt(87.2, 60.0))
        primary.addCurve(to: pt(58.0, 69.0), control1: pt(78.2, 71.2), control2: pt(67.2, 72.5))
        primary.addQuadCurve(to: pt(46.5, 63.0), control: pt(52.0, 66.8))

        // Delicate cheek tusk
        secondary.move(to: pt(46.5, 64.5))
        secondary.addQuadCurve(to: pt(54.5, 73.0), control: pt(47.8, 71.2))

        // Calm smile-eye or peaceful resting closed eye
        switch expression {
        case .calm:
            primary.move(to: pt(53.0, 47.5))
            primary.addQuadCurve(to: pt(61.0, 47.5), control: pt(57.0, 43.0))
        case .resting:
            primary.move(to: pt(53.0, 46.0))
            primary.addQuadCurve(to: pt(61.0, 46.0), control: pt(57.0, 50.2))
        }

        return (primary, secondary)
    }
}

// MARK: - Shared Components

struct MoroWidgetBrandBadge: View {
    let palette: MoroWidgetPalette
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.tileSurface)
            Circle()
                .stroke(palette.tileBorder, lineWidth: 0.75)
            MoroWidgetElephantMark(
                size: size * 0.74,
                primaryColor: palette.inkPrimary,
                secondaryColor: palette.inkSecondary
            )
            .widgetAccentable()
        }
        .frame(width: size, height: size)
    }
}

struct MoroWidgetAvatar: View {
    let account: MoroWidgetAccount?
    let avatarData: Data?
    let size: CGFloat
    let palette: MoroWidgetPalette

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.subtleSurface)

            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else if let initial = account?.preferredName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.inkPrimary)
            } else {
                MoroWidgetElephantMark(
                    size: size * 0.68,
                    primaryColor: palette.inkPrimary,
                    secondaryColor: palette.inkSecondary
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(palette.tileBorder, lineWidth: 1)
        }
        .shadow(color: palette.tileShadowColor, radius: 4, y: 2)
    }
}

struct MoroWidgetUnreadPill: View {
    let count: Int
    let palette: MoroWidgetPalette
    var compact: Bool = false

    private var label: String {
        count > 99 ? "99+" : "\(count)"
    }

    var body: some View {
        Text(label)
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.accentForeground)
            .padding(.horizontal, compact ? 4.5 : 6)
            .frame(minWidth: compact ? 16 : 20, minHeight: compact ? 16 : 19)
            .background(palette.accentTint, in: Capsule())
            .widgetAccentable()
    }
}

struct MoroWidgetEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let title: LocalizedStringKey
    var accent: MoroWidgetAccent = .default

    var body: some View {
        let palette = MoroWidgetPalette(
            colorScheme: colorScheme,
            renderingMode: renderingMode,
            accent: accent
        )

        VStack(alignment: .leading, spacing: 8) {
            MoroWidgetBrandBadge(palette: palette, size: 40)

            Spacer(minLength: 4)

            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.inkPrimary)
                .lineLimit(1)

            Text("widget.signIn.subtitle")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(MoroWidgetDestination.home.deepLinkURL)
    }
}
