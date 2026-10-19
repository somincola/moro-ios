//
//  ProfileConnectionsView.swift
//  moro
//
//  Paginated following and followers lists opened from profile statistics.
//

import Combine
import SwiftUI

@MainActor
final class ProfileConnectionsViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case collectionsHidden
        case error(String)
    }

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var didFailLoadMore = false
    @Published private(set) var transientErrorMessage: String?
    private(set) var hasMore = true

    let kind: ProfileConnectionKind

    private let accountID: String
    private let apiClient: MastodonAPI
    private let pageSize: Int

    init(
        accountID: String,
        kind: ProfileConnectionKind,
        apiClient: MastodonAPI,
        pageSize: Int = 40
    ) {
        self.accountID = accountID
        self.kind = kind
        self.apiClient = apiClient
        self.pageSize = max(1, pageSize)
    }

    func loadInitial() async {
        guard loadingState == .idle else { return }
        await loadFirstPage()
    }

    func refresh() async {
        await loadFirstPage()
    }

    func loadMoreIfNeeded(currentAccount: Account) async {
        guard currentAccount.id == accounts.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !accounts.isEmpty, !isLoadingMore else { return }

        isLoadingMore = true
        didFailLoadMore = false
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(maxID: accounts.last?.id)
            var knownIDs = Set(accounts.map(\.id))
            let uniqueAccounts = page.filter { knownIDs.insert($0.id).inserted }
            accounts.append(contentsOf: uniqueAccounts)
            hasMore = page.count == pageSize && !uniqueAccounts.isEmpty
        } catch is CancellationError {
            return
        } catch {
            if isCollectionsHiddenError(error) {
                transitionToCollectionsHidden()
            } else {
                didFailLoadMore = true
            }
        }
    }

    private func loadFirstPage() async {
        if accounts.isEmpty {
            loadingState = .loading
        }
        transientErrorMessage = nil
        didFailLoadMore = false

        do {
            let page = try await fetchPage(maxID: nil)
            var knownIDs = Set<String>()
            accounts = page.filter { knownIDs.insert($0.id).inserted }
            hasMore = page.count == pageSize
            loadingState = .loaded
        } catch is CancellationError {
            if accounts.isEmpty {
                loadingState = .idle
            }
        } catch {
            if isCollectionsHiddenError(error) {
                transitionToCollectionsHidden()
            } else if accounts.isEmpty {
                loadingState = .error(error.localizedDescription)
            } else {
                transientErrorMessage = error.localizedDescription
                loadingState = .loaded
            }
        }
    }

    private func fetchPage(maxID: String?) async throws -> [Account] {
        switch kind {
        case .following:
            return try await apiClient.fetchAccountFollowing(
                id: accountID,
                maxID: maxID,
                limit: pageSize
            )
        case .followers:
            return try await apiClient.fetchAccountFollowers(
                id: accountID,
                maxID: maxID,
                limit: pageSize
            )
        }
    }

    private func isCollectionsHiddenError(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        return apiError.httpStatusCode == 403
    }

    private func transitionToCollectionsHidden() {
        accounts = []
        hasMore = false
        didFailLoadMore = false
        transientErrorMessage = nil
        loadingState = .collectionsHidden
    }
}

struct ProfileConnectionsView: View {
    @Environment(\.appRouter) private var router
    @Environment(\.moroTheme) private var theme
    @StateObject private var viewModel: ProfileConnectionsViewModel

    init(accountID: String, kind: ProfileConnectionKind, apiClient: MastodonAPI) {
        _viewModel = StateObject(
            wrappedValue: ProfileConnectionsViewModel(
                accountID: accountID,
                kind: kind,
                apiClient: apiClient
            )
        )
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            accountList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.surfaceBase.ignoresSafeArea())
        .navigationTitle(viewModel.kind.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.surfaceBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await viewModel.loadInitial()
        }
    }

    private var contentState: ContentState {
        if viewModel.accounts.isEmpty {
            switch viewModel.loadingState {
            case .idle, .loading:
                return .loading(.list)
            case .loaded:
                return .empty(
                    EmptyStateSpec(
                        icon: "person.2",
                        title: viewModel.kind.navigationTitle,
                        message: viewModel.kind.emptyMessage,
                        actionTitle: MoroL10n.Timeline.refresh,
                        action: {
                            Task { await viewModel.refresh() }
                        }
                    )
                )
            case .collectionsHidden:
                return .empty(
                    EmptyStateSpec(
                        icon: "eye.slash",
                        title: MoroL10n.Profile.collectionsHiddenTitle,
                        message: MoroL10n.Profile.collectionsHiddenMessage
                    )
                )
            case .error(let message):
                return .error(
                    ErrorStateSpec(
                        title: MoroL10n.MentionUser.loadFailed,
                        message: message,
                        actionTitle: MoroL10n.MentionUser.retry,
                        action: {
                            Task { await viewModel.refresh() }
                        }
                    )
                )
            }
        }
        return .loaded
    }

    private var accountList: some View {
        List {
            if let transientErrorMessage = viewModel.transientErrorMessage {
                HStack(alignment: .top, spacing: theme.spacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.colors.error)
                    Text(transientErrorMessage)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, theme.spacing.xs)
                .listRowBackground(theme.colors.surfaceBase)
            }

            ForEach(viewModel.accounts) { account in
                Button {
                    router.navigate(to: .userProfile(account))
                } label: {
                    ProfileConnectionAccountRow(account: account)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(MoroL10n.Profile.openProfile(account.acct))
                .listRowInsets(EdgeInsets())
                .listRowBackground(theme.colors.surfaceBase)
                .onAppear {
                    Task {
                        await viewModel.loadMoreIfNeeded(currentAccount: account)
                    }
                }
            }

            PaginationFooter(
                isLoadingMore: viewModel.isLoadingMore,
                didFail: viewModel.didFailLoadMore,
                onRetry: {
                    Task { await viewModel.loadMore() }
                }
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(theme.colors.surfaceBase)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(theme.colors.divider)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(theme.colors.surfaceBase)
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private struct ProfileConnectionAccountRow: View {
    @Environment(\.moroTheme) private var theme

    let account: Account

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials, seed: account.placeholderSeed,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 1
                )

                Text("@\(account.acct.isEmpty ? account.username : account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: theme.spacing.s)

            Image(systemName: "chevron.right")
                .moroScaledFont(size: 11, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surfaceBase)
    }
}

private extension ProfileConnectionKind {
    var navigationTitle: String {
        switch self {
        case .following:
            return MoroL10n.Profile.statFollowing
        case .followers:
            return MoroL10n.Profile.statFollowers
        }
    }

    var emptyMessage: String {
        switch self {
        case .following:
            return MoroL10n.Profile.emptyFollowingMessage
        case .followers:
            return MoroL10n.Profile.emptyFollowersMessage
        }
    }
}
