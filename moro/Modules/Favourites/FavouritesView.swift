//
//  FavouritesView.swift
//  moro
//
//  Favourited statuses list page.
//

import SwiftUI

struct FavouritesView: View {
    @StateObject private var viewModel: FavouritesViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState

    init(apiClient: MastodonAPI) {
        _viewModel = StateObject(wrappedValue: FavouritesViewModel(apiClient: apiClient))
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            contentList
        }
        .navigationTitle(MoroL10n.Favourites.navTitle)
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
                    title: MoroL10n.Favourites.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Favourites.retry,
                    action: {
                        Task { await viewModel.loadInitial() }
                    }
                )
            )
        }
        if viewModel.statuses.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "heart",
                    title: MoroL10n.Favourites.emptyTitle,
                    message: MoroL10n.Favourites.emptyMessage,
                    actionTitle: MoroL10n.Favourites.refresh,
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
                    .background(theme.colors.surfaceBase)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.colors.borderSubtle, lineWidth: 1)
                    )
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.s)
                }

                ForEach(Array(viewModel.statuses.enumerated()), id: \.element.id) { index, status in
                    FavouriteStatusRow(
                        status: status,
                        isOwnPost: PostMoreMenuPolicy.isOwnPost(status, currentUserID: appState.currentAccount?.id),
                        onTapDetail: {
                            router.navigate(to: .statusDetail(status.displayStatus))
                        },
                        onRemoveFavourite: {
                            Task { await viewModel.removeFavourite(status) }
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
}

private struct FavouriteStatusRow: View {
    let status: Status
    let isOwnPost: Bool
    let onTapDetail: () -> Void
    let onRemoveFavourite: () -> Void
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
        .contentShape(Rectangle())
        .onTapGesture {
            onTapDetail()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onRemoveFavourite) {
                Label(MoroL10n.Favourites.unfavourite, systemImage: "heart.slash")
            }
        }
    }
}

#Preview {
    let appState = AppState()
    let interceptor = AuthInterceptor(tokenProvider: appState)
    let client = MastodonClient(authInterceptor: interceptor)
    return FavouritesView(apiClient: client)
        .environmentObject(appState)
        .moroTheme(MoroTheme())
}
