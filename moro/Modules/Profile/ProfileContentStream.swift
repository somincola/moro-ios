//
//  ProfileContentStream.swift
//  moro
//
//  Isolated status stream for the selected profile tab.
//

import SwiftUI

struct ProfileContentStream: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.cacheManager) private var cacheManager

    @ObservedObject var viewModel: ProfileViewModel

    let apiClient: MastodonAPI
    let postActions: (Status) -> PostActions

    var body: some View {
        LazyVStack(spacing: 0) {
            if viewModel.selectedTab == .posts && !viewModel.pinnedStatuses.isEmpty {
                PinnedStatusSection(
                    pinnedStatuses: viewModel.pinnedStatuses,
                    translationAPIClient: apiClient,
                    accountCache: cacheManager.accountCache,
                    postActions: postActions
                )

                pinnedSectionSeparator
            }

            contentRows
        }
        .background(theme.colors.surfaceBase)
    }

    private var pinnedSectionSeparator: some View {
        VStack(spacing: 0) {
            MoroDivider()
            theme.colors.surfaceSubtle
                .frame(height: theme.spacing.s)
            MoroDivider()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var contentRows: some View {
        switch contentState {
        case .loading(let skeletonStyle):
            ContentSkeletonView(style: skeletonStyle)
        case .empty(let spec):
            EmptyStateView(spec: spec)
                .frame(minHeight: 320)
        case .error(let spec):
            ErrorStateView(spec: spec)
                .frame(minHeight: 320)
        case .loaded:
            loadedRows
        }
    }

    @ViewBuilder
    private var loadedRows: some View {
        ForEach(Array(viewModel.currentStatuses.enumerated()), id: \.element.id) {
            index, status in
            let prefetchWindowSize = 2
            let isNearBottom = viewModel.currentStatuses.count - index <= 3

            VStack(alignment: .leading, spacing: 0) {
                TimelinePostRow(
                    status: status,
                    threadContext: .none,
                    translationAPIClient: apiClient,
                    accountCache: cacheManager.accountCache,
                    actions: postActions(status)
                )
                .onAppear {
                    loadVisibleStatus(
                        status,
                        index: index,
                        prefetchWindowSize: prefetchWindowSize,
                        isNearBottom: isNearBottom
                    )
                }

                MoroDivider()
            }
        }

        let selectedTab = viewModel.selectedTab
        if viewModel.isLoadingMore(selectedTab) || viewModel.didFailLoadMore(selectedTab) {
            PaginationFooter(
                isLoadingMore: viewModel.isLoadingMore(selectedTab),
                didFail: viewModel.didFailLoadMore(selectedTab),
                onRetry: retrySelectedTabPagination
            )
        }
    }

    private var contentState: ContentState {
        switch viewModel.tabLoadState(for: viewModel.selectedTab) {
        case .notLoaded, .loading:
            return .loading(.timeline)
        case .error(let message):
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Timeline.loadFailed,
                    message: message,
                    actionTitle: MoroL10n.Timeline.retry,
                    action: retrySelectedTab
                )
            )
        case .loaded:
            if viewModel.currentStatuses.isEmpty {
                return .empty(emptyStateSpec)
            }
            return .loaded
        }
    }

    private var emptyStateSpec: EmptyStateSpec {
        switch viewModel.selectedTab {
        case .posts:
            return EmptyStateSpec(
                icon: "square.and.pencil",
                title: MoroL10n.Profile.emptyPostsTitle,
                message: MoroL10n.Profile.emptyPostsMessage
            )
        case .replies:
            return EmptyStateSpec(
                icon: "bubble.left.and.bubble.right",
                title: MoroL10n.Profile.emptyRepliesTitle,
                message: MoroL10n.Profile.emptyRepliesMessage
            )
        case .media:
            return EmptyStateSpec(
                icon: "photo.on.rectangle",
                title: MoroL10n.Profile.emptyMediaTitle,
                message: MoroL10n.Profile.emptyMediaMessage
            )
        }
    }

    private func loadVisibleStatus(
        _ status: Status,
        index: Int,
        prefetchWindowSize: Int,
        isNearBottom: Bool
    ) {
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

    private func retrySelectedTab() {
        let tab = viewModel.selectedTab
        Task { await viewModel.retryTab(tab) }
    }

    private func retrySelectedTabPagination() {
        Task { await viewModel.loadMore() }
    }
}
