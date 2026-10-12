//
//  TranslationSettingsView.swift
//  moro
//
//  Basic translation preferences for status content translation.
//

import SwiftUI

struct TranslationSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme

    var body: some View {
        MoroSettingsList {
            Section {
                ForEach(AppSettings.ContentTranslationMode.allCases, id: \.rawValue) { mode in
                    MoroChoiceRow(
                        title: mode.localizedName,
                        detail: nil,
                        isSelected: settings.contentTranslationMode == mode
                    ) {
                        settings.contentTranslationMode = mode
                    }
                }
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Translation.providerSectionTitle)
            }

            Section {
                HStack {
                    Text(MoroL10n.Translation.targetLanguageLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Text(settings.preferredTranslationTargetLanguageSummary)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            } footer: {
                Text(MoroL10n.Translation.settingsFooter)
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Translation.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TranslationSettingsView()
    }
    .moroTheme(MoroTheme())
}
