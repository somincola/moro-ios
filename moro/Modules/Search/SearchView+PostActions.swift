import SwiftUI

extension SearchContentView {
    var handlers: PostInteractionHandlers {
        PostInteractionHandlers(
            interactionService: interactionService, actionSurface: actionSurface,
            postMenuActionCenter: postMenuActionCenter, apiClient: apiClient,
            currentUserID: appState.currentAccount?.id, router: router, onRemoveStatus: nil
        )
    }

    var searchWithPostActionSurfaces: some View {
        searchContent
        .sheet(item: $actionSurface.boostDialogStatus) { status in
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
                onBoost: {
                    Task {
                        await interactionService.toggleBoost(status, askFirst: false)
                    }
                },
                onUnboost: {
                    Task {
                        await interactionService.toggleBoost(status, askFirst: false)
                    }
                },
                onQuote: {
                    actionSurface.startQuote(from: status)
                },
                onDismiss: {
                    actionSurface.dismissBoostDialog()
                }
            )
            .moroSheetSurface(
                detents: [
                    .height(
                        BoostOrQuoteDialog.preferredDetentHeight(
                            quoteButtonTitle: quoteInfo.title,
                            quoteButtonSubtitle: quoteInfo.subtitle
                        ))
                ]
            )
        }
        .alert(item: Binding(
            get: { interactionService.activeAlert },
            set: { _ in interactionService.activeAlert = nil }
        )) { alert in
            switch alert {
            case .confirmBoost(let didConfirm):
                return Alert(
                    title: Text(MoroL10n.StatusDetail.confirmBoostTitle),
                    message: Text(MoroL10n.StatusDetail.confirmBoostMessage),
                    primaryButton: .default(Text(MoroL10n.StatusDetail.boost)) {
                        didConfirm(true)
                    },
                    secondaryButton: .cancel(Text(MoroL10n.StatusDetail.cancel)) {
                        didConfirm(false)
                    }
                )
            }
        }
        .alert(MoroL10n.ComposeDrafts.deleteConfirmTitle, isPresented: Binding(
            get: { actionSurface.statusToDelete != nil },
            set: {
                if !$0 { actionSurface.clearDeleteRequest() }
            }
        )) {
            Button(MoroL10n.ComposeDrafts.deleteAndRedraftAction, role: .destructive) {
                if let status = actionSurface.statusToDelete {
                    handlers.performDelete(status, redraft: true)
                }
                actionSurface.clearDeleteRequest()
            }
            Button(MoroL10n.ComposeDrafts.deleteAction, role: .destructive) {
                if let status = actionSurface.statusToDelete {
                    handlers.performDelete(status)
                }
                actionSurface.clearDeleteRequest()
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {
                actionSurface.clearDeleteRequest()
            }
        } message: {
            Text(MoroL10n.ComposeDrafts.deleteConfirmMessage)
        }
        .fullScreenCover(item: $actionSurface.composeContext) { wrapper in
            ComposeView(
                context: wrapper.context,
                apiClient: apiClient,
                currentUserID: appState.currentAccount?.id,
                initialDraft: wrapper.draft
            ) { status in
                FeedCoordinator.shared.publishUpdate(.post(status))
            }
            .environmentObject(appState)
        }
        .sheet(item: $actionSurface.reportStatus) { status in
            ReportView(
                status: status,
                apiClient: apiClient,
                onDismiss: { actionSurface.dismissReport() }
            )
            .moroSheetSurface(detents: [.large])
        }
    }
}
