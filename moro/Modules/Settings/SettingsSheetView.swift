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
}
