import SwiftUI

struct ReadingSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.activeAccountKey) private var activeAccountKey

    let apiClient: MastodonAPI?

    var body: some View {
        List {
            Section {
                Toggle(MoroL10n.GeneralSettings.newPostBanner, isOn: $settings.timelineInAppNewPostBannerEnabled)
                    .accessibilityIdentifier("settings.reading.newPostBanner")
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Settings.timeline)
            } footer: {
                Text(MoroL10n.GeneralSettings.timelineMediaFooter)
            }

            Section {
                Toggle(MoroL10n.GeneralSettings.autoplayGIFs, isOn: $settings.autoplayGIFs)
                    .accessibilityIdentifier("settings.reading.autoplayGIFs")
                Toggle(MoroL10n.GeneralSettings.playAnimations, isOn: $settings.playAnimations)
                    .accessibilityIdentifier("settings.reading.playAnimations")
                Picker(MoroL10n.GeneralSettings.videoAutoplayMode, selection: $settings.videoAutoplayMode) {
                    ForEach(AppSettings.VideoAutoplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.colors.textSecondary)
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.ProfileEditing.media)
            } footer: {
                Text(MoroL10n.GeneralSettings.autoplayFooter)
            }

            Section {
                NavigationLink {
                    SensitiveMediaChoiceView()
                } label: {
                    LabeledContent(MoroL10n.Settings.sensitiveMediaDisplay) {
                        Text(settings.sensitiveMediaDisplay.title)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .accessibilityIdentifier("settings.sensitiveMedia")
                Toggle(MoroL10n.Settings.expandContentWarnings, isOn: $settings.expandContentWarnings)
                    .accessibilityIdentifier("settings.expandContentWarnings")
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Settings.sensitiveSection)
            } footer: {
                Text(MoroL10n.Settings.sensitiveFooter)
            }

            Section {
                Picker(MoroL10n.GeneralSettings.openLinksIn, selection: $settings.openLinksIn) {
                    ForEach(AppSettings.OpenLinksIn.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.colors.textSecondary)
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.GeneralSettings.linksSection)
            }

            Section {
                NavigationLink {
                    TranslationSettingsView()
                } label: {
                    LabeledContent(MoroL10n.Translation.settingsLabel) {
                        Text(settings.contentTranslationModeSummary)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .accessibilityIdentifier("settings.translation")
            }

            if let apiClient {
                Section {
                    NavigationLink(MoroL10n.Settings.profileReading) {
                        ProfileDisplaySettingsView(apiClient: apiClient, accountKey: activeAccountKey, scope: .local)
                    }
                    .accessibilityIdentifier("settings.profileReading")
                } footer: {
                    Text(MoroL10n.Settings.profileLocalScope)
                }
            }
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome(separators: .visible)
        .textCase(nil)
        .navigationTitle(MoroL10n.Settings.readingMedia)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SensitiveMediaChoiceView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        MoroChoicePage(
            heading: MoroL10n.Settings.sensitiveMediaDisplay,
            hint: MoroL10n.Settings.sensitiveMediaDisplayHint,
            options: SensitiveMediaDisplay.allCases.map {
                MoroChoiceOption(value: $0, title: $0.title, detail: $0.detail)
            },
            selection: settings.sensitiveMediaDisplay,
            accessibilityPrefix: "settings.sensitiveMedia"
        ) { settings.sensitiveMediaDisplay = $0 }
    }
}
