//
//  MoroSettingsListChrome.swift
//  moro
//
//  Shared flat list chrome for settings-family pages.
//

import SwiftUI

struct MoroSettingsListChrome: ViewModifier {
    @Environment(\.moroTheme) private var theme
    let separators: Visibility

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .listSectionSpacing(24)
            .listRowSeparator(separators)
            .listRowSeparatorTint(theme.colors.borderSubtle)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .tint(theme.colors.primary500)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func moroSettingsListChrome(separators: Visibility = .hidden) -> some View {
        modifier(MoroSettingsListChrome(separators: separators))
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
