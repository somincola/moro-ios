//
//  HashtagView.swift
//  moro
//
//  Displays timeline for a specific hashtag.
//

import SwiftUI

struct HashtagRouteView: View {
    @Environment(\.activeAccountKey) private var accountKey
    let hashtag: String
    let apiClient: MastodonAPI
    var body: some View {
        HashtagView(hashtag: hashtag, apiClient: apiClient).id(accountKey)
    }
}

struct HashtagView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.cacheManager) private var cacheManager
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState
    @StateObject private var topicFollow: TopicFollowModel
    @StateObject private var viewModel: HashtagViewModel
    @StateObject private var interactionService: PostInteractionService
    @StateObject private var actionSurface = PostActionSurfaceCenter()

    let hashtag: String
    private let apiClient: MastodonAPI
    @StateObject private var postMenuActionCenter: PostMenuActionCenter

    init(hashtag: String, apiClient: MastodonAPI) {
        self.hashtag = hashtag
        self.apiClient = apiClient
        _topicFollow = StateObject(wrappedValue: TopicFollowModel(apiClient: apiClient, name: hashtag))
        _postMenuActionCenter = StateObject(
            wrappedValue: PostMenuActionCenter(apiClient: apiClient))
        _interactionService = StateObject(
            wrappedValue: PostInteractionService(apiClient: apiClient))
        _viewModel = StateObject(wrappedValue: HashtagViewModel(
            apiClient: apiClient,
            hashtag: hashtag
        ))
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.statuses.indexed(), id: \.element.id) { index, status in
                        let prefetchWindowSize = 6
                        let isNearBottom = viewModel.statuses.count - index <= 3
                        TimelinePostRow(
                            status: status,
                            threadContext: .none,
                            accountCache: cacheManager.accountCache,
                            actions: buildPostActions(for: status)
                        )
                        .onAppear {
                            Task {
                                if index < prefetchWindowSize {
                                    await StatusDetailPrefetchCoordinator.shared.prefetchStatusAndQuoteIfNeeded(
                                        for: status.displayStatus,
                                        apiClient: apiClient,
                                        threadCache: cacheManager.threadCache,
                                        accountCache: cacheManager.accountCache
                                    )
                                }
                                if isNearBottom {
                                    await viewModel.loadMore()
                                }
                            }
                        }

                        MoroDivider()
                    }

                    PaginationFooter(
                        isLoadingMore: isLoadingMore,
                        didFail: viewModel.loadMoreFailed,
                        onRetry: { Task { await viewModel.loadMore() } }
                    )
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if topicFollow.error != nil {
                HStack {
                    Text(MoroL10n.Topics.actionFailed)
                        .font(theme.typography.caption)
                    Spacer()
                    Button(MoroL10n.Compose.retry) {
                        Task {
                            if topicFollow.following == nil { await topicFollow.load() }
                            else { await topicFollow.toggle() }
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(topicFollow.isBusy)
                    .accessibilityIdentifier("topic.retry")
                }
                .padding(.horizontal, theme.spacing.m)
                .background(theme.colors.surfaceBase)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if topicFollow.following == nil { await topicFollow.load() }
                        else { await topicFollow.toggle() }
                    }
                } label: {
                    if topicFollow.isBusy {
                        ProgressView().frame(minWidth: 44, minHeight: 44)
                    } else {
                        Text(topicFollow.following == true ? MoroL10n.Topics.following : MoroL10n.Topics.follow)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .disabled(topicFollow.isBusy || topicFollow.following == nil)
                .accessibilityIdentifier("topic.follow")
                .accessibilityLabel(topicFollow.following == true ? MoroL10n.Topics.unfollow : MoroL10n.Topics.follow)
            }
        }
        .task { await topicFollow.load() }
        .navigationTitle("#\(hashtag)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadInitial()
        }
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
        .fullScreenCover(item: $actionSurface.composeContext) { wrapper in
            ComposeView(
                context: wrapper.context,
                apiClient: apiClient,
                currentUserID: appState.currentAccount?.id,
                initialDraft: wrapper.draft,
                onDismiss: { actionSurface.composeContext = nil }
            ) { _ in
                Task { await viewModel.refresh() }
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

    private var isLoadingMore: Bool {
        if case .loadingMore = viewModel.loadingState { return true }
        return false
    }

    private var contentState: ContentState {
        if viewModel.statuses.isEmpty {
            switch viewModel.loadingState {
            case .loading, .refreshing:
                return .loading(.timeline)
            case .error(let error):
                return .error(
                    ErrorStateSpec(
                        title: MoroL10n.Hashtag.loadFailed,
                        message: error.localizedDescription,
                        actionTitle: MoroL10n.Hashtag.retry,
                        action: {
                            Task { await viewModel.loadInitial() }
                        }
                    )
                )
            case .idle, .loadingMore:
                return .empty(
                    EmptyStateSpec(
                        icon: "number",
                        title: MoroL10n.Hashtag.emptyTitle,
                        message: MoroL10n.Hashtag.emptyMessage(hashtag),
                        actionTitle: MoroL10n.Hashtag.refresh,
                        action: {
                            Task { await viewModel.refresh() }
                        }
                    )
                )
            }
        }
        return .loaded
    }

    // MARK: - Helpers

    private var handlers: PostInteractionHandlers {
        PostInteractionHandlers(
            interactionService: interactionService,
            actionSurface: actionSurface,
            postMenuActionCenter: postMenuActionCenter,
            apiClient: apiClient,
            currentUserID: appState.currentAccount?.id,
            router: router,
            onRemoveStatus: { id in viewModel.removeStatus(id: id) }
        )
    }

    private func buildPostActions(for status: Status) -> PostActions {
        handlers.buildPostActions(
            for: status,
            onPollVote: { pollID, choices in
                await viewModel.votePoll(pollID: pollID, choices: choices)
            }
        )
    }

}
