import SwiftUI

struct BookmarksRouteView: View {
    @Environment(\.activeAccountKey) private var accountKey
    let apiClient: MastodonAPI
    var body: some View {
        BookmarksView(apiClient: apiClient, library: BookmarkLibraryStore(accountKey: accountKey))
            .id(accountKey)
    }
}

struct BookmarksView: View {
    @StateObject private var viewModel: BookmarksViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState

    init(apiClient: MastodonAPI, library: BookmarkLibraryStore? = nil) {
        _viewModel = StateObject(wrappedValue: BookmarksViewModel(apiClient: apiClient, library: library))
    }

    var body: some View {
        ContentStateContainer(state: contentState) { contentList }
            .navigationTitle(MoroL10n.Bookmarks.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: MoroL10n.BookmarkReading.search)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(BookmarksViewModel.ReadingFilter.allCases, id: \.self) { filter in
                            Button { viewModel.readingFilter = filter } label: {
                                if viewModel.readingFilter == filter { Label(filter.title, systemImage: "checkmark") }
                                else { Text(filter.title) }
                            }
                            .accessibilityIdentifier("bookmarks.filter.\(filter.rawValue)")
                        }
                    } label: {
                        Label(viewModel.readingFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("bookmarks.filter")
                }
            }
            .task { await viewModel.loadInitial() }
    }

    private var contentState: ContentState {
        if viewModel.statuses.isEmpty, viewModel.isLoading { return .loading(.timeline) }
        if viewModel.statuses.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(ErrorStateSpec(title: MoroL10n.Bookmarks.loadFailed,
                message: error.localizedDescription, actionTitle: MoroL10n.Bookmarks.retry,
                action: { Task { await viewModel.refresh() } }))
        }
        if viewModel.statuses.isEmpty, !viewModel.hasMore {
            return .empty(EmptyStateSpec(icon: "bookmark", title: MoroL10n.Bookmarks.emptyTitle,
                message: MoroL10n.Bookmarks.emptyMessage, actionTitle: MoroL10n.Bookmarks.refresh,
                action: { Task { await viewModel.refresh() } }))
        }
        return .loaded
    }

    private var contentList: some View {
        List {
            Group {
                Text(MoroL10n.BookmarkReading.scope)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.s)

                if let error = viewModel.transientErrorMessage {
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .accessibilityIdentifier("bookmarks.error")
                        if viewModel.isOfflineSnapshot {
                            Button(MoroL10n.Bookmarks.retry) { Task { await viewModel.refresh() } }
                                .accessibilityIdentifier("bookmarks.retry")
                        }
                    }
                    .padding(theme.spacing.m)
                }

                if viewModel.filteredStatuses.isEmpty {
                    Text(MoroL10n.BookmarkReading.noMatches)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(theme.spacing.l)
                        .accessibilityIdentifier("bookmarks.noMatches")
                }

                ForEach(viewModel.filteredStatuses) { status in
                    bookmarkRow(status)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await viewModel.removeBookmark(status) } } label: {
                                Label(MoroL10n.Bookmarks.remove, systemImage: "bookmark.slash")
                            }
                            .disabled(viewModel.isLoading || viewModel.removingIDs.contains(status.id))
                            .accessibilityIdentifier("bookmarks.swipeRemove.\(status.id)")
                        }
                }

                if viewModel.hasMore, !viewModel.isOfflineSnapshot {
                    HStack {
                        Spacer()
                        if viewModel.isLoading { ProgressView() }
                        else {
                            Button(viewModel.loadMoreFailed ? MoroL10n.Common.loadMoreRetry : MoroL10n.BookmarkReading.loadMore) {
                                Task { await viewModel.loadMore() }
                            }
                            .accessibilityIdentifier("bookmarks.loadMore")
                        }
                        Spacer()
                    }
                    .frame(minHeight: 52)
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(theme.colors.surfaceBase)
        }
        .listStyle(.plain)
        .moroReadableListMargins()
        .scrollContentBackground(.hidden)
        .background(theme.colors.surfaceBase)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await viewModel.refresh() }
    }

    private func bookmarkRow(_ status: Status) -> some View {
        let isRead = viewModel.readIDs.contains(status.displayStatus.id)
        let isRemoving = viewModel.removingIDs.contains(status.id)
        let nav = PostNavigationActionCenter.handlers(for: status, detailStatus: status.displayStatus) {
            router.navigate(to: $0)
        }
        return VStack(spacing: 0) {
            PostCard(status: status, actions: PostActions(navigation: nav,
                isOwnPost: PostMoreMenuPolicy.isOwnPost(status, currentUserID: appState.currentAccount?.id)),
                showToolbar: false)
                .contentShape(Rectangle())
                .onTapGesture { router.navigate(to: .statusDetail(status.displayStatus)) }
            HStack {
                Label(isRead ? MoroL10n.BookmarkReading.read : MoroL10n.BookmarkReading.unread,
                      systemImage: isRead ? "checkmark.circle" : "circle")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer()
                if isRemoving { ProgressView() }
                Menu {
                    Button(isRead ? MoroL10n.BookmarkReading.markUnread : MoroL10n.BookmarkReading.markRead) {
                        viewModel.setRead(!isRead, status: status)
                    }
                    .accessibilityIdentifier("bookmarks.toggleRead.\(status.id)")
                    Button(MoroL10n.Bookmarks.remove, role: .destructive) {
                        Task { await viewModel.removeBookmark(status) }
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("bookmarks.remove.\(status.id)")
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(MoroL10n.BookmarkReading.actions)
                .accessibilityIdentifier("bookmarks.actions.\(status.id)")
            }
            .padding(.horizontal, theme.spacing.m)
            MoroDivider()
        }
        .opacity(isRemoving ? 0.55 : 1)
        .disabled(isRemoving)
    }
}

#Preview {
    let appState = AppState()
    return NavigationStack {
        BookmarksView(apiClient: MastodonClient(authInterceptor: AuthInterceptor(tokenProvider: appState)))
    }
    .environmentObject(appState)
    .moroTheme(MoroTheme())
}
