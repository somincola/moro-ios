import SwiftUI

/// The presenting screen owns these sheets even when the source post scrolls offscreen.
struct PostInteractionSheets: ViewModifier {
    @ObservedObject var actionSurface: PostActionSurfaceCenter
    @ObservedObject var interactionService: PostInteractionService
    let apiClient: MastodonAPI
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
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
            .fullScreenCover(item: $actionSurface.composeContext) { wrapper in
                ComposeView(
                    context: wrapper.context,
                    apiClient: apiClient,
                    currentUserID: appState.currentAccount?.id,
                    initialDraft: wrapper.draft,
                    onDismiss: { actionSurface.composeContext = nil }
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
            }
    }
}

/// Lists with navigation-only cards still offer the full set of actions when opening media.
struct MediaPreviewActionSource: ViewModifier {
    let apiClient: MastodonAPI
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState
    @StateObject private var surface = PostActionSurfaceCenter()
    @StateObject private var interactions: PostInteractionService
    @StateObject private var menu: PostMenuActionCenter

    init(apiClient: MastodonAPI) {
        self.apiClient = apiClient
        _interactions = StateObject(wrappedValue: PostInteractionService(apiClient: apiClient))
        _menu = StateObject(wrappedValue: PostMenuActionCenter(apiClient: apiClient))
    }

    func body(content: Content) -> some View {
        content
            .environment(\.mediaPreviewHandlers, PostInteractionHandlers(
                interactionService: interactions, actionSurface: surface, postMenuActionCenter: menu,
                apiClient: apiClient, currentUserID: appState.currentAccount?.id, router: router, onRemoveStatus: nil))
            .modifier(PostInteractionSheets(actionSurface: surface, interactionService: interactions, apiClient: apiClient))
    }
}
