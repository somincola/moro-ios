//
//  MoroSettingsListChrome.swift
//  moro
//
//  Shared flat list chrome for settings-family pages.
//

import SwiftUI

struct MoroSettingsListChrome: ViewModifier {
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .tint(theme.colors.primary500)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func moroSettingsListChrome() -> some View {
        modifier(MoroSettingsListChrome())
    }
}
