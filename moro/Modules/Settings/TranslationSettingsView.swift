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
        List {
            Section {
                ForEach(AppSettings.ContentTranslationMode.allCases, id: \.rawValue) { mode in
                    Button {
                        settings.contentTranslationMode = mode
                    } label: {
                        HStack {
                            Text(mode.localizedName)
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            if settings.contentTranslationMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .moroScaledFont(size: 14, weight: .semibold)
                                    .foregroundStyle(theme.colors.primary500)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(MoroL10n.Translation.providerSectionTitle)
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
