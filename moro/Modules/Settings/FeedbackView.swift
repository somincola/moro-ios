import SwiftUI

enum MoroFeedbackDraft {
    static let author = "@acacius@m.somincola.org"

    static func make(accountID: String?) -> ComposeDraft {
        let now = Date()
        return ComposeDraft(
            id: UUID().uuidString, accountID: accountID, category: .manual,
            target: ComposeDraftTarget(kind: .newPost),
            payload: ComposeDraftPayload(
                content: "\(author) #Moro\n\n", contentWarning: "", isContentWarningActive: false,
                visibility: .public, mediaAttachments: [], isPollActive: false,
                pollOptions: ["", ""], pollMultiple: false, pollExpiresIn: 86_400,
                isSchedulingEnabled: false, scheduledAt: nil, selectedLanguageCode: "",
                quotePolicyRawValue: ComposeViewModel.QuotePolicy.anyone.rawValue
            ), createdAt: now, updatedAt: now
        )
    }
}

struct FeedbackView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.moroTheme) private var theme
    let apiClient: MastodonAPI?
    @State private var draft: ComposeDraft?

    var body: some View {
        MoroSettingsList {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MoroL10n.AppSupport.invitation).font(.headline)
                    Text(MoroL10n.AppSupport.invitationDetail).font(.subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .padding(.vertical, 8)
            }
            Section {
                FeedbackEmailButton {
                    Label(MoroL10n.About.feedbackEmail, systemImage: "envelope")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("feedback.email")
                if apiClient != nil, appState.currentAccount != nil {
                    Button {
                        draft = MoroFeedbackDraft.make(accountID: appState.currentAccount?.id)
                    } label: {
                        Label(MoroL10n.AppSupport.mastodonFeedback, systemImage: "at")
                    }
                    .accessibilityIdentifier("feedback.mastodon")
                }
            } footer: {
                Text(MoroL10n.AppSupport.feedbackPrivacy)
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.AppSupport.feedback)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { draft in
            if let apiClient {
                ComposeView(context: .newPost, apiClient: apiClient,
                            currentUserID: appState.currentAccount?.id, initialDraft: draft,
                            onDismiss: { self.draft = nil })
                    .environmentObject(appState)
                    .moroSheetSurface(detents: [.large], cornerRadius: 20)
            }
        }
    }
}
