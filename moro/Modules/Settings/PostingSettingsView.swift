import SwiftUI

struct PostingSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme

    let domain: String?
    let apiClient: MastodonAPI?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PostLanguagePickerView(
                        title: MoroL10n.Language.defaultPickerTitle,
                        selectedLanguageCode: $settings.defaultPostLanguage,
                        defaultBehavior: .serverDefault(languageCode: settings.serverDefaultPostLanguage)
                    )
                } label: {
                    LabeledContent(MoroL10n.GeneralSettings.defaultPostLanguage) {
                        Text(settings.defaultPostLanguageSummary)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .accessibilityIdentifier("settings.postLanguage")
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.PrivacySafety.sectionDefaults)
            }

            Section {
                Toggle(MoroL10n.GeneralSettings.askBeforePostingWithoutAltText, isOn: $settings.askBeforePostingWithoutAltText)
                    .accessibilityIdentifier("settings.confirm.altText")
                Toggle(MoroL10n.GeneralSettings.askBeforeUnfollow, isOn: $settings.askBeforeUnfollowingAUser)
                Toggle(MoroL10n.GeneralSettings.askBeforeMute, isOn: $settings.askBeforeMutingAUser)
                Toggle(MoroL10n.GeneralSettings.askBeforeBlock, isOn: $settings.askBeforeBlockingAUser)
                Toggle(MoroL10n.GeneralSettings.askBeforeBoost, isOn: $settings.askBeforeBoostingAPost)
                Toggle(MoroL10n.GeneralSettings.askBeforeDelete, isOn: $settings.askBeforeDeletingAPost)
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.GeneralSettings.confirmBeforeActionSection)
            }

            Section {
                NavigationLink {
                    if let domain {
                        EmojiManagementView(domain: domain, apiClient: apiClient)
                    } else {
                        EmojiManagementUnavailableView()
                    }
                } label: {
                    Label(MoroL10n.Settings.emojiManagement, systemImage: "face.smiling")
                }
                .accessibilityIdentifier("settings.emoji")
            }
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome(separators: .visible)
        .textCase(nil)
        .navigationTitle(MoroL10n.Settings.postingInteractions)
        .navigationBarTitleDisplayMode(.inline)
    }
}
