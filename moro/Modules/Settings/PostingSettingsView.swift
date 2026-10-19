import SwiftUI

struct PostingSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme

    let domain: String?
    let apiClient: MastodonAPI?

    var body: some View {
        MoroSettingsList {
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

                if let apiClient {
                    NavigationLink {
                        DefaultVisibilityChoiceView(apiClient: apiClient)
                    } label: {
                        LabeledContent(MoroL10n.PrivacySafety.defaultVisibility) {
                            Text(settings.defaultPostVisibility.localizedName)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("settings.defaultVisibility")
                }
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

/// Default visibility is an account field on the server; the choice is optimistic and
/// rolls back if the server rejects it.
private struct DefaultVisibilityChoiceView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var appState: AppState
    @State private var isSaving = false
    @State private var saveFailed = false

    let apiClient: MastodonAPI

    var body: some View {
        MoroChoicePage(
            heading: MoroL10n.PrivacySafety.defaultVisibility,
            hint: MoroL10n.PrivacySafety.visibilityHint,
            footnote: MoroL10n.Settings.serverScope,
            errorMessage: saveFailed ? MoroL10n.PrivacySafety.toastSyncFailed : nil,
            options: AppSettings.PostVisibility.allCases.map {
                MoroChoiceOption(value: $0, title: $0.localizedName, detail: $0.choiceDetail)
            },
            selection: settings.defaultPostVisibility,
            isBusy: isSaving,
            accessibilityPrefix: "settings.visibility"
        ) { visibility in
            Task { await save(visibility) }
        }
    }

    private func save(_ visibility: AppSettings.PostVisibility) async {
        let previous = settings.defaultPostVisibility
        settings.defaultPostVisibility = visibility
        isSaving = true
        saveFailed = false
        do {
            appState.currentAccount = try await PrivacySettingsSync.push(settings, using: apiClient)
        } catch {
            settings.defaultPostVisibility = previous
            saveFailed = true
            AppFeedbackCenter.shared.showError(MoroL10n.PrivacySafety.toastSyncFailed)
        }
        isSaving = false
    }
}

private extension AppSettings.PostVisibility {
    var choiceDetail: String {
        switch self {
        case .public: return MoroL10n.PrivacySafety.visibilityPublicDetail
        case .unlisted: return MoroL10n.PrivacySafety.visibilityUnlistedDetail
        case .followersOnly: return MoroL10n.PrivacySafety.visibilityFollowersDetail
        case .mentionedOnly: return MoroL10n.PrivacySafety.visibilityMentionedDetail
        }
    }
}
