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
    @ObservedObject private var feedbackCenter = AppFeedbackCenter.shared

    let apiClient: MastodonAPI?
    var showsCloseButton = true

    var body: some View {
        NavigationStack {
            if showsCloseButton {
                settingsPage
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            MoroNavigationControlButton(kind: .close) {
                                dismiss()
                            }
                            .accessibilityIdentifier("settings.sheet.close")
                        }
                    }
                    .accessibilityAction(.escape) { dismiss() }
            } else {
                settingsPage
            }
        }
        // Monochrome back buttons, matching the close button and page accents.
        .tint(theme.colors.primary500)
        .overlay(alignment: .bottom) {
            if let message = feedbackCenter.currentMessage, case .error = message.kind {
                MoroNoticePill(icon: "exclamationmark", text: message.text)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, MoroLayoutMetrics.contentHorizontalInset)
                    .padding(.bottom, 16)
                    .onTapGesture { feedbackCenter.dismiss() }
                    .accessibilityIdentifier("settings.saveErrorNotice")
            }
        }
    }

    private var settingsPage: some View {
        SettingsView(apiClient: apiClient)
            .toolbarBackground(theme.colors.surfaceBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
