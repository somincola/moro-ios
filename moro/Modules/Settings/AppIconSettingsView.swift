//
//  AppIconSettingsView.swift
//  moro
//
//  App icon picker, rendered as a Section inside the display settings gallery.
//

import SwiftUI
import UIKit

/// App icon grid rendered as a `Section` in its own settings gallery.
struct AppIconSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSwitchingAppIcon = false
    @State private var appIconSwitchErrorMessage: String?

    private var iconGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]
        }
        return [GridItem(.adaptive(minimum: 68, maximum: 76), spacing: 10)]
    }

    var body: some View {
        Section {
            LazyVGrid(columns: iconGridColumns, alignment: .leading, spacing: 12) {
                ForEach(AppSettings.AppIconChoice.allCases, id: \.rawValue) { appIcon in
                    appIconCard(appIcon)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .onAppear {
                settings.appIcon = AppIconManager.shared.currentChoice
            }
            .alert(MoroL10n.GeneralSettings.iconSwitchFailed, isPresented: Binding(
                get: { appIconSwitchErrorMessage != nil },
                set: { presented in
                    if !presented {
                        appIconSwitchErrorMessage = nil
                    }
                }
            )) {
                Button(MoroL10n.Common.ok, role: .cancel) {
                    appIconSwitchErrorMessage = nil
                }
            } message: {
                Text(appIconSwitchErrorMessage ?? MoroL10n.GeneralSettings.retryLater)
            }
        } header: {
            Text(MoroL10n.GeneralSettings.appIconSection)
                .moroScaledFont(size: 13, weight: .regular)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.none)
        } footer: {
            if isSwitchingAppIcon {
                Text(MoroL10n.GeneralSettings.switchingIconFooter)
            } else {
                Text(MoroL10n.GeneralSettings.iconAppliesFooter)
            }
        }
    }

    @ViewBuilder
    private func appIconCard(_ appIcon: AppSettings.AppIconChoice) -> some View {
        let isSelected = settings.appIcon == appIcon
        Button {
            switchAppIcon(appIcon)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    appIconPreviewImage(for: appIcon)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(
                                    isSelected ? theme.colors.primary500 : theme.colors.borderSubtle,
                                    lineWidth: isSelected ? 1.8 : 1
                                )
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .moroScaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(theme.colors.primary500)
                            .background(
                                Circle()
                                    .fill(theme.colors.background)
                            )
                            .offset(x: 5, y: -5)
                    }
                }
                .dynamicTypeSize(.xSmall ... .xxxLarge)

                Text(appIcon.title)
                    .font(theme.typography.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(
                        isSelected ? theme.colors.textPrimary : theme.colors.textSecondary
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                    .allowsTightening(!dynamicTypeSize.isAccessibilitySize)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appIcon.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(isSwitchingAppIcon)
    }

    @ViewBuilder
    private func appIconPreviewImage(for appIcon: AppSettings.AppIconChoice) -> some View {
        if UIImage(named: appIcon.previewAssetName) != nil {
            Image(appIcon.previewAssetName)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.colors.primary50)
                Image(systemName: "app.fill")
                    .moroScaledFont(size: 24, weight: .semibold)
                    .foregroundStyle(theme.colors.primary500)
            }
        }
    }

    private func switchAppIcon(_ appIcon: AppSettings.AppIconChoice) {
        guard settings.appIcon != appIcon else { return }

        isSwitchingAppIcon = true
        Task { @MainActor in
            defer { isSwitchingAppIcon = false }

            do {
                try await AppIconManager.shared.apply(appIcon)
                settings.appIcon = appIcon
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                appIconSwitchErrorMessage = error.localizedDescription
                AppFeedbackCenter.shared.showError(MoroL10n.GeneralSettings.iconSwitchError)
            }
        }
    }
}
