//
//  GeneralSettingsView.swift
//  moro
//
//  General settings view with appearance, design, and behavior preferences.
//

import SwiftUI

struct GeneralSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme

    var body: some View {
        List {
            Section {
                NavigationLink {
                    DisplaySettingsView()
                } label: {
                    HStack {
                        Text(MoroL10n.Display.title)
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        Circle()
                            .fill(theme.colors.contentLink)
                            .frame(width: 16, height: 16)
                            .accessibilityLabel(settings.themeColor.title)
                    }
                }
                .accessibilityIdentifier("settings.display")
            } header: {
                Text(MoroL10n.Settings.appearance)
            }

            AppIconSettingsView()

            Section {
                NavigationLink {
                    PostLanguagePickerView(
                        title: MoroL10n.Language.defaultPickerTitle,
                        selectedLanguageCode: $settings.defaultPostLanguage,
                        defaultBehavior: .serverDefault(
                            languageCode: settings.serverDefaultPostLanguage
                        )
                    )
                } label: {
                    HStack {
                        Text(MoroL10n.GeneralSettings.defaultPostLanguage)
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        Text(settings.defaultPostLanguageSummary)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                NavigationLink {
                    TranslationSettingsView()
                } label: {
                    HStack {
                        Text(MoroL10n.Translation.settingsLabel)
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        Text(settings.contentTranslationModeSummary)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Picker(MoroL10n.GeneralSettings.openLinksIn, selection: $settings.openLinksIn) {
                    ForEach(AppSettings.OpenLinksIn.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.colors.textSecondary)
            } header: {
                Text(MoroL10n.GeneralSettings.languageLinksSection)
            }

            Section {
                Toggle(MoroL10n.GeneralSettings.newPostBanner, isOn: $settings.timelineInAppNewPostBannerEnabled)
                Toggle(MoroL10n.GeneralSettings.autoplayGIFs, isOn: $settings.autoplayGIFs)
                Toggle(MoroL10n.GeneralSettings.playAnimations, isOn: $settings.playAnimations)

                Picker(MoroL10n.GeneralSettings.videoAutoplayMode, selection: $settings.videoAutoplayMode) {
                    ForEach(AppSettings.VideoAutoplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.colors.textSecondary)
            } header: {
                Text(MoroL10n.GeneralSettings.timelineMediaSection)
            } footer: {
                Text("\(MoroL10n.GeneralSettings.timelineMediaFooter)\(MoroL10n.GeneralSettings.autoplayFooter)")
            }

            Section {
                Toggle(MoroL10n.GeneralSettings.askBeforePostingWithoutAltText, isOn: $settings.askBeforePostingWithoutAltText)
                Toggle(MoroL10n.GeneralSettings.askBeforeUnfollow, isOn: $settings.askBeforeUnfollowingAUser)
                Toggle(MoroL10n.GeneralSettings.askBeforeMute, isOn: $settings.askBeforeMutingAUser)
                Toggle(MoroL10n.GeneralSettings.askBeforeBlock, isOn: $settings.askBeforeBlockingAUser)
                Toggle(MoroL10n.GeneralSettings.askBeforeBoost, isOn: $settings.askBeforeBoostingAPost)
                Toggle(MoroL10n.GeneralSettings.askBeforeDelete, isOn: $settings.askBeforeDeletingAPost)
            } header: {
                Text(MoroL10n.GeneralSettings.confirmBeforeActionSection)
            }

        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Settings.readingBrowsingSection)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
            .moroTheme(MoroTheme())
    }
}
