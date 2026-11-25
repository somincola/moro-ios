//
//  MoroSettingsListChrome.swift
//  moro
//
//  One visual system for every settings-family page: a pure content canvas
//  (`surfaceBase`), flat full-width rows without card boxes or row dividers,
//  crisp monochrome icons and uniform row height matching the primary tabs.
//

import SwiftUI

enum MoroSettingsMetrics {
    /// Every settings row shares this minimum, toggles and links alike.
    static let minimumRowHeight: CGFloat = 50
    static let sectionSpacing: CGFloat = 20
    static let iconColumnWidth: CGFloat = 24
    static let iconTitleSpacing: CGFloat = 14
    static let iconPointSize: CGFloat = 18
    /// Non-List settings pages (editors, server details) share the same page inset
    /// and subtle surface containers on the unified canvas.
    static let pageHorizontalInset: CGFloat = 20
    static let cardCornerRadius: CGFloat = 12
}

/// Row backgrounds and separator visibility belong on the list's content so SwiftUI
/// applies them to every row and section across all settings screens.
struct MoroSettingsList<Content: View>: View {
    @Environment(\.moroTheme) private var theme
    private let separators: Visibility
    private let content: Content

    init(separators: Visibility = .hidden, @ViewBuilder content: () -> Content) {
        self.separators = separators
        self.content = content()
    }

    var body: some View {
        List {
            content
                .listRowBackground(theme.colors.surfaceBase)
                .listRowSeparator(separators)
                .listRowSeparatorTint(theme.colors.divider)
                .listSectionSeparator(.hidden)
                .listSectionSeparatorTint(theme.colors.divider)
        }
    }
}

struct MoroSettingsListChrome: ViewModifier {
    @Environment(\.moroTheme) private var theme
    let separators: Visibility

    func body(content: Content) -> some View {
        content
            .listStyle(.grouped)
            .listSectionSpacing(MoroSettingsMetrics.sectionSpacing)
            .listRowSeparator(separators)
            .listRowSeparatorTint(theme.colors.divider)
            .listSectionSeparator(.hidden)
            .listSectionSeparatorTint(theme.colors.divider)
            .environment(\.defaultMinListRowHeight, MoroSettingsMetrics.minimumRowHeight)
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(theme.colors.surfaceBase)
            // No List-wide foregroundStyle: it would also recolor section headers and
            // footers. Row building blocks (labels, switches, choice rows) set
            // `textPrimary` themselves.
            .labelStyle(MoroSettingsRowLabelStyle())
            .tint(theme.colors.primary500)
            .toolbarBackground(theme.colors.surfaceBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Same reading width as the timeline: rows stop stretching across a wide
            // display (iPhone Duo's inner screen); nothing changes on iPhone in portrait.
            .moroReadableListMargins()
    }
}

extension View {
    func moroSettingsListChrome(separators: Visibility = .hidden) -> some View {
        modifier(MoroSettingsListChrome(separators: separators))
    }

    /// Page chrome for settings screens that are not a `List` (scrolling detail/editor pages).
    func moroSettingsPageChrome() -> some View {
        modifier(MoroSettingsPageChrome())
    }
}

private struct MoroSettingsPageChrome: ViewModifier {
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.colors.surfaceBase)
            .tint(theme.colors.primary500)
            .toolbarBackground(theme.colors.surfaceBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .moroReadableListMargins()
    }
}

private struct MoroSettingsCard: ViewModifier {
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: MoroSettingsMetrics.cardCornerRadius, style: .continuous)
        content
            .background(theme.colors.surfaceSubtle, in: shape)
            .overlay {
                shape.strokeBorder(theme.colors.borderSubtle, lineWidth: 0.5)
            }
    }
}

extension View {
    /// A subtle surface block for non-`List` settings pages on the unified canvas.
    func moroSettingsCard() -> some View {
        modifier(MoroSettingsCard())
    }
}

/// Settings row label: a fixed monochrome icon column, then the title.
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
                .foregroundStyle(tint ?? theme.colors.textPrimary)
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
            .fontWeight(.semibold)
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
