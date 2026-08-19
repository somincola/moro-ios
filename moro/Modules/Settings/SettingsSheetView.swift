//
//  SettingsSheetView.swift
//  moro
//
//  Root modal container for Settings and its internal navigation flow.
//

import SwiftUI

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme

    let apiClient: MastodonAPI?

    var body: some View {
        NavigationStack {
            SettingsView(apiClient: apiClient)
                .toolbarBackground(theme.colors.groupedBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        MoroNavigationControlButton(kind: .close) {
                            dismiss()
                        }
                    }
                }
                .accessibilityAction(.escape) {
                    dismiss()
                }
        }
    }
}
