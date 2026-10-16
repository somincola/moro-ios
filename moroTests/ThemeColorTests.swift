import SwiftUI
import Testing
import UIKit

@testable import moro

@MainActor
struct ThemeColorTests {
    @Test(arguments: [ColorScheme.light, .dark], [ColorSchemeContrast.standard, .increased])
    func settingsCardsKeepSystemBaseColorInsideSheets(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) {
        let base = UITraitCollection { traits in
            traits.userInterfaceStyle = scheme == .dark ? .dark : .light
            traits.userInterfaceLevel = .base
            traits.accessibilityContrast = contrast == .increased ? .high : .normal
        }
        let sheet = base.modifyingTraits { $0.userInterfaceLevel = .elevated }
        let colors = MoroColors(colorScheme: scheme, colorSchemeContrast: contrast)
        #expect(UIColor(colors.groupedSurface).resolvedColor(with: sheet).isEqual(
            UIColor.secondarySystemGroupedBackground.resolvedColor(with: base)
        ))
    }

    @Test(arguments: MoroThemeColor.allCases, [ColorScheme.light, .dark])
    func selectionLeavesAuthorAndSemanticColorsUnchanged(_ selection: MoroThemeColor, _ scheme: ColorScheme) {
        let baseline = MoroColors(colorScheme: scheme)
        let colors = MoroColors(colorScheme: scheme, themeColor: selection)
        for (original, current) in [
            (baseline.primary500, colors.primary500),
            (baseline.primaryForeground, colors.primaryForeground),
            (baseline.textPrimary, colors.textPrimary),
            (baseline.textSecondary, colors.textSecondary),
            (baseline.boostActive, colors.boostActive),
            (baseline.bookmarkActive, colors.bookmarkActive),
            (baseline.unreadIndicator, colors.unreadIndicator),
            (baseline.error, colors.error),
        ] {
            #expect(UIColor(original).isEqual(UIColor(current)))
        }
    }

    @Test(arguments: MoroThemeColor.allCases, [ColorScheme.light, .dark])
    func linksMeetContrastRequirements(_ selection: MoroThemeColor, _ scheme: ColorScheme) throws {
        let standard = MoroColors(colorScheme: scheme, themeColor: selection)
        let increased = MoroColors(
            colorScheme: scheme, themeColor: selection, colorSchemeContrast: .increased
        )
        for background in [
            standard.surfaceBase, standard.surfaceSubtle, standard.surfaceElevated, standard.groupedBackground,
        ] {
            let normalRatio = try contrast(standard.contentLink, background)
            let increasedRatio = try contrast(increased.contentLink, background)
            #expect(normalRatio >= 4.5)
            #expect(increasedRatio >= normalRatio)
        }
        #expect(UIColor(standard.contentLink).isEqual(UIColor(standard.themeTint)))
        #expect(try contrast(standard.themeTintForeground, standard.themeTint) >= 4.5)
    }

    @Test
    func UIKitPaletteDetectsLinkColorAndContrastChanges() {
        let original = MoroTheme()
        let purple = MoroTheme(themeColor: .purple)
        let increased = MoroTheme(colorSchemeContrast: .increased)
        let custom = MoroTheme(themeColor: .custom, customThemeColor: 0xAABBCC)
        let changedCustom = MoroTheme(themeColor: .custom, customThemeColor: 0x112233)
        #expect(!original.uiKitPalette.matches(purple))
        #expect(!original.uiKitPalette.matches(increased))
        #expect(!custom.uiKitPalette.matches(changedCustom))
        #expect(purple.uiKitPalette.matches(purple))
        #expect(purple.uiKitPalette.contentLink.isEqual(UIColor(purple.colors.contentLink)))
    }

    @Test
    func selectedColorIsPersisted() {
        let settings = AppSettings.shared
        let defaults = UserDefaults.standard
        let previousColor = settings.themeColor
        let previousValue = defaults.object(forKey: "contentLinkColor")
        let previousRGB = settings.customThemeColor
        let previousCustomValue = defaults.object(forKey: "customThemeColor")
        defer {
            settings.themeColor = previousColor
            settings.customThemeColor = previousRGB
            if let previousValue {
                defaults.set(previousValue, forKey: "contentLinkColor")
            } else {
                defaults.removeObject(forKey: "contentLinkColor")
            }
            if let previousCustomValue {
                defaults.set(previousCustomValue, forKey: "customThemeColor")
            } else {
                defaults.removeObject(forKey: "customThemeColor")
            }
        }
        settings.themeColor = .green
        #expect(defaults.string(forKey: "contentLinkColor") == "green")
        settings.customThemeColor = 0xE8DEAD
        settings.themeColor = .custom
        #expect(defaults.string(forKey: "contentLinkColor") == "custom")
        #expect(defaults.integer(forKey: "customThemeColor") == 0xE8DEAD)
    }

    @Test(arguments: [UInt32(0x000000), 0xFFFFFF, 0x808080, 0xF4F5F7, 0x16181A, 0xFFFF00, 0x00FF00, 0xFF00FF], [ColorScheme.light, .dark])
    func customColorsRemainReadable(_ rgb: UInt32, _ scheme: ColorScheme) throws {
        for contrastMode in [ColorSchemeContrast.standard, .increased] {
            let colors = MoroColors(
                colorScheme: scheme, themeColor: .custom, customThemeColor: rgb,
                colorSchemeContrast: contrastMode
            )
            #expect(colors.customThemeColor == rgb)
            for background in [colors.surfaceBase, colors.surfaceSubtle, colors.surfaceElevated, colors.groupedBackground] {
                #expect(try contrast(colors.contentLink, background) >= (contrastMode == .increased ? 7 : 4.5))
            }
            #expect(try contrast(colors.themeTintForeground, colors.themeTint) >= 4.5)
        }
        let readable = scheme == .dark ? UInt32(0xFFFFFF) : UInt32(0x000000)
        let colors = MoroColors(colorScheme: scheme, themeColor: .custom, customThemeColor: readable)
        #expect(UIColor(colors.contentLink).isEqual(UIColor(Color(hex: readable))))
    }

    @Test
    func inboxBadgeUpdatesWithThemeEvenWhenUnreadCountIsUnchanged() throws {
        let empty = AnyView(EmptyView())
        let controller = MainShellViewController(
            coordinator: RootTabCoordinator(), theme: MoroTheme(), unreadInboxCount: 3,
            currentUserAvatarURL: nil, contentVersion: "theme-test",
            homeView: empty, exploreView: empty, inboxView: empty, meView: empty,
            routeView: { _, _ in empty }
        )
        controller.loadViewIfNeeded()
        let tabs = try #require(controller.children.first as? UITabBarController)
        let item = try #require(tabs.tabBar.items?[2])
        var previous = item.image
        var previousScheme = MoroTheme().colorScheme
        for theme in [
            MoroTheme(themeColor: .pink),
            MoroTheme(colorScheme: .dark, themeColor: .green),
            MoroTheme(themeColor: .custom, customThemeColor: 0xFFFFFF),
            MoroTheme(themeColor: .custom, customThemeColor: 0x112233),
        ] {
            controller.apply(
                theme: theme, unreadInboxCount: 3, currentUserAvatarURL: nil,
                contentVersion: "theme-test", homeView: empty, exploreView: empty,
                inboxView: empty, meView: empty, routeView: { _, _ in empty }
            )
            // Unread is the bell's own red badge layer, not a system badge; the count
            // lives in the VoiceOver label. The red dot is fixed, while the bell follows
            // the tab's text colors, so a light/dark change must redraw it.
            #expect(item.badgeValue == nil)
            #expect(item.image?.renderingMode == .alwaysOriginal)
            if theme.colorScheme != previousScheme {
                #expect(item.image !== previous, "The badged bell is redrawn when its colors change")
            }
            #expect(item.accessibilityLabel == MoroL10n.Navigation.inboxUnread(3))
            previous = item.image
            previousScheme = theme.colorScheme
        }
        controller.apply(
            theme: MoroTheme(), unreadInboxCount: 0, currentUserAvatarURL: nil,
            contentVersion: "theme-test", homeView: empty, exploreView: empty,
            inboxView: empty, meView: empty, routeView: { _, _ in empty }
        )
        #expect(item.image?.renderingMode != .alwaysOriginal)
        #expect(item.accessibilityLabel == MainTab.inbox.title)
    }

    @Test(arguments: MoroThemeColor.allCases)
    func nativeRichTextUsesSelectedColorWithoutChangingURLs(_ selection: MoroThemeColor) throws {
        let url = try #require(URL(string: "https://example.com"))
        let color = UIColor(MoroTheme(themeColor: selection).colors.contentLink)
        let view = MixedTextEmojiView(
            elements: [
                .mention(username: "@moro", url: url), .text(" "),
                .link(text: "example.com", url: url), .text(" "),
                .hashtag(tag: "#Moro", url: url),
            ],
            emojiSize: 16, textColor: .label, linkColor: color,
            codeBackgroundColor: .secondarySystemBackground
        )
        let text = view.buildAttributedString(
            emojiAssets: [:], textColor: .label, linkColor: color,
            codeBackgroundColor: .secondarySystemBackground, underlinesLinks: false
        )
        for token in ["@moro", "example.com", "#Moro"] {
            let range = (text.string as NSString).range(of: token)
            try #require(range.location != NSNotFound)
            let renderedColor = try #require(text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor)
            #expect(renderedColor.isEqual(color))
            #expect(text.attribute(.link, at: range.location, effectiveRange: nil) as? URL == url)
        }
    }

    private func contrast(_ foreground: Color, _ background: Color) throws -> Double {
        let front = try luminance(UIColor(foreground))
        let back = try luminance(UIColor(background))
        return (max(front, back) + 0.05) / (min(front, back) + 0.05)
    }

    private func luminance(_ color: UIColor) throws -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        try #require(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722
    }
}
