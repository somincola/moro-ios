//
//  MoroSettingsListChrome.swift
//  moro
//
//  One visual system for every settings-family page: a grouped page background,
//  system inset-grouped cards (`groupedSurface`), theme text colors, quiet gray
//  row icons and a uniform row height.
//

import SwiftUI

enum MoroSettingsMetrics {
    /// Every settings row shares this minimum, toggles and links alike.
    static let minimumRowHeight: CGFloat = 50
    static let sectionSpacing: CGFloat = 24
    static let iconColumnWidth: CGFloat = 24
    static let iconTitleSpacing: CGFloat = 12
    static let iconPointSize: CGFloat = 17
    /// Non-List settings pages (editors, server details) mirror the inset-grouped
    /// card geometry so they sit in the same family as List pages.
    static let pageHorizontalInset: CGFloat = 20
    static let cardCornerRadius: CGFloat = 10
}

/// Row backgrounds belong on the list's content, so every settings list shares this container.
struct MoroSettingsList<Content: View>: View {
    @Environment(\.moroTheme) private var theme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        List {
            content.listRowBackground(theme.colors.groupedSurface)
        }
    }
}

struct MoroSettingsListChrome: ViewModifier {
    @Environment(\.moroTheme) private var theme
    let separators: Visibility

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .listSectionSpacing(MoroSettingsMetrics.sectionSpacing)
            .listRowSeparator(separators)
            .listRowSeparatorTint(theme.colors.borderSubtle)
            .environment(\.defaultMinListRowHeight, MoroSettingsMetrics.minimumRowHeight)
            .contentMargins(.top, 12, for: .scrollContent)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(theme.colors.groupedBackground)
            // No List-wide foregroundStyle: it would also recolor section headers and
            // footers. Row building blocks (labels, switches, choice rows) set
            // `textPrimary` themselves.
            .labelStyle(MoroSettingsRowLabelStyle())
            .tint(theme.colors.primary500)
            .toolbarBackground(theme.colors.groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Same reading width as the timeline: rows stop stretching across a wide
            // display (iPhone Duo's inner screen); nothing changes on iPhone in portrait.
            .moroReadableListMargins()
    }
}

extension View {
    func moroSettingsListChrome(separators: Visibility = .visible) -> some View {
        modifier(MoroSettingsListChrome(separators: separators))
    }

    /// Page chrome for settings screens that are not a `List` (scrolling cards).
    func moroSettingsPageChrome() -> some View {
        modifier(MoroSettingsPageChrome())
    }
}

private struct MoroSettingsPageChrome: ViewModifier {
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.colors.groupedBackground)
            .tint(theme.colors.primary500)
            .toolbarBackground(theme.colors.groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .moroReadableListMargins()
    }
}

private struct MoroSettingsCard: ViewModifier {
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(
                theme.colors.groupedSurface,
                in: RoundedRectangle(cornerRadius: MoroSettingsMetrics.cardCornerRadius, style: .continuous)
            )
    }
}

extension View {
    /// A borderless grouped card for settings pages that are not a `List`.
    func moroSettingsCard() -> some View {
        modifier(MoroSettingsCard())
    }
}

/// Settings row label: a fixed gray icon column, then the title. Separators start
/// at the title so icon rows line up with plain rows below them.
struct MoroSettingsRowLabelStyle: LabelStyle {
    @Environment(\.moroTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var iconWidth = MoroSettingsMetrics.iconColumnWidth
    /// Destructive rows pass their role color so icon and title read as one.
    private let tint: Color?

    init(tint: Color? = nil) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: MoroSettingsMetrics.iconTitleSpacing) {
            configuration.icon
                .moroScaledFont(size: MoroSettingsMetrics.iconPointSize, weight: .regular)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint ?? theme.colors.textSecondary)
                .frame(width: iconWidth)
            configuration.title
                .foregroundStyle(tint ?? theme.colors.textPrimary)
        }
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + iconWidth + MoroSettingsMetrics.iconTitleSpacing
        }
    }
}

struct MoroSettingsSectionHeader: View {
    @Environment(\.moroTheme) private var theme
    let title: String

    var body: some View {
        Text(title)
            .font(theme.typography.caption)
            .fontWeight(.medium)
            .foregroundStyle(theme.colors.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

extension Section where Parent == MoroSettingsSectionHeader, Footer == EmptyView, Content: View {
    /// `Section("Title")` in the settings header style (no uppercasing, quiet caption).
    init(moroHeader title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { MoroSettingsSectionHeader(title: title) })
    }
}

/// The one selection mark used across settings (choice pages, presets, the
/// current account): a filled circle with a check, or an empty ring.
typealias MoroSelectionIndicator = ReportSelectionIndicator
