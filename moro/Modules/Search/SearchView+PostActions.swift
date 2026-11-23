import SwiftUI

extension SearchContentView {
    var handlers: PostInteractionHandlers {
        PostInteractionHandlers(
            interactionService: interactionService, actionSurface: actionSurface,
            postMenuActionCenter: postMenuActionCenter, apiClient: apiClient,
            appState: appState, router: router, onRemoveStatus: nil
        )
    }

    var searchWithPostActionSurfaces: some View {
        searchContent
            .modifier(PostInteractionSheets(actionSurface: actionSurface, interactionService: interactionService,
                                            apiClient: apiClient))
            .alert(MoroL10n.ComposeDrafts.deleteConfirmTitle, isPresented: Binding(
                get: { actionSurface.deleteRequest != nil },
                set: {
                    if !$0 { actionSurface.clearDeleteRequest() }
                }
            )) {
                Button(
                    actionSurface.deleteRequest?.shouldRedraft == true
                        ? MoroL10n.ComposeDrafts.deleteAndRedraftAction
                        : MoroL10n.ComposeDrafts.deleteAction,
                    role: .destructive
                ) {
                    if let request = actionSurface.deleteRequest {
                        handlers.performDelete(request.status, redraft: request.shouldRedraft)
                    }
                    actionSurface.clearDeleteRequest()
                }
                Button(MoroL10n.Common.cancel, role: .cancel) {
                    actionSurface.clearDeleteRequest()
                }
            } message: {
                Text(MoroL10n.ComposeDrafts.deleteConfirmMessage)
            }
    }
}
