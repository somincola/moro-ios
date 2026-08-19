//
//  BookmarksView.swift
//  moro
//
//  Bookmarked statuses list page (MVP).
//

import SwiftUI

struct BookmarksView: View {
    @StateObject private var viewModel: BookmarksViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState
    @AppStorage("bookmarks.swipeHintDismissed.v1") private var didDismissSwipeHint = false

    init(apiClient: MastodonAPI) {
        _viewModel = StateObject(wrappedValue: BookmarksViewModel(apiClient: apiClient))
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            contentList
        }
        .navigationTitle(MoroL10n.Bookmarks.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitial()
        }
    }

    private var isLoadingMore: Bool {
        if case .loadingMore = viewModel.loadingState { return true }
        return false
    }

    private var contentState: ContentState {
        if viewModel.statuses.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.timeline)
        }
        if viewModel.statuses.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Bookmarks.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Bookmarks.retry,
                    action: {
                        Task { await viewModel.loadInitial() }
                    }
                )
            )
        }
        if viewModel.statuses.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "bookmark",
                    title: MoroL10n.Bookmarks.emptyTitle,
                    message: MoroL10n.Bookmarks.emptyMessage,
                    actionTitle: MoroL10n.Bookmarks.refresh,
                    action: {
                        Task { await viewModel.refresh() }
                    }
                )
            )
        }
        return .loaded
    }

    @ViewBuilder
    private var contentList: some View {
        VStack(spacing: 0) {
            if !didDismissSwipeHint {
                swipeHintRow
                    .padding(.horizontal, theme.spacing.l)
                    .background(theme.colors.surfaceBase)

                MoroDivider()
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let transientErrorMessage = viewModel.transientErrorMessage {
                        HStack(alignment: .top, spacing: theme.spacing.s) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(theme.colors.error)
                                .padding(.top, 2)
                            Text(transientErrorMessage)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                        }
                        .padding(theme.spacing.s)
                        .background(theme.colors.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, theme.spacing.m)
                        .padding(.vertical, theme.spacing.s)
                    }

                    ForEach(Array(viewModel.statuses.enumerated()), id: \.element.id) { index, status in
                        BookmarkStatusRow(
                            status: status,
                            isOwnPost: PostMoreMenuPolicy.isOwnPost(
                                status,
                                currentUserID: appState.currentAccount?.id
                            ),
                            isRemoving: viewModel.removingIDs.contains(status.id),
                            onTapDetail: {
                                router.navigate(to: .statusDetail(status.displayStatus))
                            },
                            onRemoveBookmark: {
                                Task { await viewModel.removeBookmark(status) }
                            },
                            onNavigate: { route in
                                router.navigate(to: route)
                            }
                        )

                        MoroDivider()

                        if viewModel.statuses.count - index <= 3 {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task { await viewModel.loadMore() }
                                }
                        }
                    }

                    PaginationFooter(
                        isLoadingMore: isLoadingMore,
                        didFail: viewModel.loadMoreFailed,
                        onRetry: { Task { await viewModel.loadMore() } }
                    )
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(theme.colors.surfaceBase)
    }

    private var swipeHintRow: some View {
        HStack(alignment: .center, spacing: theme.spacing.m) {
            Image(systemName: "bookmark.slash")
                .moroScaledFont(size: 15, weight: .regular)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 20)

            Text(MoroL10n.Bookmarks.swipeHint)
                .moroScaledFont(size: 13, weight: .regular, relativeTo: .footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: theme.spacing.s)

            Button(MoroL10n.Bookmarks.gotIt) {
                withAnimation(.easeOut(duration: 0.18)) {
                    didDismissSwipeHint = true
                }
            }
            .moroScaledFont(size: 13, weight: .semibold, relativeTo: .footnote)
            .foregroundStyle(theme.colors.textPrimary)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}

private struct BookmarkStatusRow: View {
    let status: Status
    let isOwnPost: Bool
    let isRemoving: Bool
    let onTapDetail: () -> Void
    let onRemoveBookmark: () -> Void
    let onNavigate: (Route) -> Void

    var body: some View {
        let nav = PostNavigationActionCenter.handlers(
            for: status,
            detailStatus: status.displayStatus,
            navigate: onNavigate
        )

        PostCard(
            status: status,
            actions: PostActions(
                navigation: nav,
                isOwnPost: isOwnPost
            ),
            showToolbar: false
        )
        .opacity(isRemoving ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapDetail)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isRemoving {
                Button(role: .destructive, action: onRemoveBookmark) {
                    Label(MoroL10n.Bookmarks.remove, systemImage: "bookmark.slash")
                }
            }
        }
        .disabled(isRemoving)
    }
}

#Preview {
    let appState = AppState()
    let interceptor = AuthInterceptor(tokenProvider: appState)
    let client = MastodonClient(authInterceptor: interceptor)
    return BookmarksView(apiClient: client)
        .environmentObject(appState)
        .moroTheme(MoroTheme())
}
