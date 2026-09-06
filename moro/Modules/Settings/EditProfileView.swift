import SwiftUI

/// A compact hub. Each destination owns its draft and its save boundary.
struct EditProfileView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.activeAccountKey) private var activeAccountKey
    @EnvironmentObject private var appState: AppState
    let apiClient: MastodonAPI
    let currentAccount: Account?

    private var account: Account? { appState.currentAccount ?? currentAccount }

    var body: some View {
        List {
            if let account {
                Section {
                    VStack(spacing: 0) {
                        if let url = account.profileHeaderURL {
                            MoroNetworkImage(url: url)
                                .frame(height: 112)
                                .clipped()
                        }
                        HStack(spacing: 14) {
                            MoroAvatar(imageURL: account.profileAvatarURL,
                                staticImageURL: account.avatarURL,
                                initials: account.displayNameInitials, size: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.displayNameFormatted)
                                    .font(theme.typography.bodyStrong)
                                    .foregroundStyle(theme.colors.textPrimary)
                                Text("@\(account.acct)")
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                NavigationLink {
                    ProfileBasicsEditor(apiClient: apiClient, currentAccount: account)
                } label: {
                    ProfileEditorSummaryRow(title: MoroL10n.EditProfile.sectionBasicInfo,
                        summary: account?.note.isEmpty == false
                            ? HTMLParser.stripHTML(account?.note ?? "")
                            : MoroL10n.EditProfile.fieldBio)
                }
                .accessibilityIdentifier("profile.edit.basic")
                NavigationLink {
                    ProfileFieldsEditor(apiClient: apiClient, account: account)
                } label: {
                    ProfileEditorSummaryRow(title: MoroL10n.EditProfile.sectionExtraFields,
                        summary: account?.fields.isEmpty == false
                            ? account!.fields.map { HTMLParser.stripHTML($0.name) }.joined(separator: " · ")
                            : MoroL10n.ProfileEditing.emptyFields)
                }
                .accessibilityIdentifier("profile.edit.fields")
                NavigationLink {
                    FeaturedTagsEditor(apiClient: apiClient)
                } label: {
                    ProfileEditorSummaryRow(title: MoroL10n.ProfileEditing.featuredTags,
                        summary: MoroL10n.ProfileEditing.tagHint)
                }
                .accessibilityIdentifier("profile.edit.featuredTags")
                NavigationLink {
                    ProfileDisplaySettingsView(apiClient: apiClient, accountKey: activeAccountKey)
                } label: {
                    ProfileEditorSummaryRow(title: MoroL10n.ProfileEditing.displaySettings,
                        summary: MoroL10n.ProfileEditing.showTags)
                }
                .accessibilityIdentifier("profile.edit.display")
            }
        }
        .profileEditorChrome()
        .navigationTitle(MoroL10n.EditProfile.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("profile.edit.overview")
    }
}

struct ProfileEditorSummaryRow: View {
    @Environment(\.moroTheme) private var theme
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(theme.typography.body).foregroundStyle(theme.colors.textPrimary)
            Text(summary)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
