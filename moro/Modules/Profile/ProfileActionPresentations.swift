//
//  ProfileActionPresentations.swift
//  moro
//
//  Presentation boundary for profile and post actions.
//

import SwiftUI

struct ProfileActionPresentationState {
    var showUnfollowConfirmation = false
    var showMuteConfirmation = false
    var showBlockConfirmation = false
    var pendingAction: (() -> Void)?
    var reportAccount: Account?
    var addToListAccount: Account?
}

private struct ProfileActionPresentationsModifier: ViewModifier {
    @Binding var presentation: ProfileActionPresentationState

    @ObservedObject var actionSurface: PostActionSurfaceCenter
    @ObservedObject var interactionService: PostInteractionService
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var appState: AppState

    let fallbackAccount: Account?
    let apiClient: MastodonAPI
    let refreshProfile: () async -> Void
    let performDelete: (Status, Bool) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $actionSurface.boostDialogStatus) { status in
                boostDialog(for: status)
            }
            .fullScreenCover(item: $actionSurface.composeContext) { wrapper in
                ComposeView(
                    context: wrapper.context,
                    apiClient: apiClient,
                    currentUserID: appState.currentAccount?.id,
                    initialDraft: wrapper.draft,
                    onDismiss: { actionSurface.composeContext = nil }
                ) { _ in
                    Task {
                        await refreshProfile()
                    }
                }
                .environmentObject(appState)
            }
            .sheet(item: $actionSurface.reportStatus) { status in
                ReportView(
                    status: status,
                    apiClient: apiClient,
                    onDismiss: actionSurface.dismissReport
                )
                .moroSheetSurface(detents: [.large])
            }
            .sheet(item: $presentation.reportAccount) { account in
                AccountReportView(
                    account: account,
                    apiClient: apiClient,
                    onDismiss: { presentation.reportAccount = nil }
                )
                .moroSheetSurface(detents: [.large])
            }
            .sheet(item: $presentation.addToListAccount) { account in
                AddToListSheet(account: account, apiClient: apiClient)
                    .moroSheetSurface(detents: [.medium, .large])
            }
            .alert(
                MoroL10n.ComposeDrafts.deleteConfirmTitle,
                isPresented: deleteConfirmationBinding
            ) {
                Button(MoroL10n.ComposeDrafts.deleteAndRedraftAction, role: .destructive) {
                    performRequestedDelete(redraft: true)
                }
                Button(MoroL10n.ComposeDrafts.deleteAction, role: .destructive) {
                    performRequestedDelete(redraft: false)
                }
                Button(MoroL10n.Common.cancel, role: .cancel) {
                    actionSurface.clearDeleteRequest()
                }
            } message: {
                Text(MoroL10n.ComposeDrafts.deleteConfirmMessage)
            }
            .alert(
                MoroL10n.MentionUser.unfollowTitle,
                isPresented: $presentation.showUnfollowConfirmation
            ) {
                confirmationButtons(confirmTitle: MoroL10n.MentionUser.unfollowAction)
            } message: {
                if let account = viewModel.account ?? fallbackAccount {
                    Text(MoroL10n.MentionUser.unfollowMessage(account.username))
                }
            }
            .alert(
                MoroL10n.MentionUser.muteTitle,
                isPresented: $presentation.showMuteConfirmation
            ) {
                confirmationButtons(confirmTitle: MoroL10n.MentionUser.muteAction)
            } message: {
                if let account = viewModel.account ?? fallbackAccount {
                    Text(MoroL10n.MentionUser.muteMessage(account.username))
                }
            }
            .alert(
                MoroL10n.MentionUser.blockTitle,
                isPresented: $presentation.showBlockConfirmation
            ) {
                confirmationButtons(confirmTitle: MoroL10n.MentionUser.blockAction)
            } message: {
                if let account = viewModel.account ?? fallbackAccount {
                    Text(MoroL10n.MentionUser.blockMessage(account.username))
                }
            }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { actionSurface.statusToDelete != nil },
            set: {
                if !$0 {
                    actionSurface.clearDeleteRequest()
                }
            }
        )
    }

    @ViewBuilder
    private func boostDialog(for status: Status) -> some View {
        let quoteInfo = QuoteButtonInfo.forStatus(
            status,
            currentUserID: appState.currentAccount?.id
        )

        BoostOrQuoteDialog(
            status: status,
            isBoosted: status.reblogged,
            canQuote: quoteInfo.isEnabled,
            quoteButtonTitle: quoteInfo.title,
            quoteButtonSubtitle: quoteInfo.subtitle,
            onBoost: toggleBoost(status),
            onUnboost: toggleBoost(status),
            onQuote: {
                actionSurface.startQuote(from: status)
            },
            onDismiss: actionSurface.dismissBoostDialog
        )
        .moroSheetSurface(
            detents: [
                .height(
                    BoostOrQuoteDialog.preferredDetentHeight(
                        quoteButtonTitle: quoteInfo.title,
                        quoteButtonSubtitle: quoteInfo.subtitle
                    )
                )
            ]
        )
    }

    private func toggleBoost(_ status: Status) -> () -> Void {
        {
            Task {
                await interactionService.toggleBoost(status, askFirst: false)
            }
        }
    }

    @ViewBuilder
    private func confirmationButtons(confirmTitle: String) -> some View {
        Button(MoroL10n.Common.cancel, role: .cancel) {
            presentation.pendingAction = nil
        }
        Button(confirmTitle, role: .destructive) {
            presentation.pendingAction?()
            presentation.pendingAction = nil
        }
    }

    private func performRequestedDelete(redraft: Bool) {
        if let status = actionSurface.statusToDelete {
            performDelete(status, redraft)
        }
        actionSurface.clearDeleteRequest()
    }
}

extension View {
    func profileActionPresentations(
        presentation: Binding<ProfileActionPresentationState>,
        actionSurface: PostActionSurfaceCenter,
        interactionService: PostInteractionService,
        viewModel: ProfileViewModel,
        appState: AppState,
        fallbackAccount: Account?,
        apiClient: MastodonAPI,
        refreshProfile: @escaping () async -> Void,
        performDelete: @escaping (Status, Bool) -> Void
    ) -> some View {
        modifier(
            ProfileActionPresentationsModifier(
                presentation: presentation,
                actionSurface: actionSurface,
                interactionService: interactionService,
                viewModel: viewModel,
                appState: appState,
                fallbackAccount: fallbackAccount,
                apiClient: apiClient,
                refreshProfile: refreshProfile,
                performDelete: performDelete
            )
        )
    }
}
