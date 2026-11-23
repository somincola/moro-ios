//
//  ListMembersView.swift
//  moro
//

import Combine
import SwiftUI

struct ListMembersView: View {
    let list: MastodonList
    @Environment(\.moroTheme) private var theme
    @FocusState private var searchFocused: Bool
    @StateObject private var viewModel: ListMembersViewModel

    init(list: MastodonList, apiClient: MastodonAPI) {
        self.list = list
        _viewModel = StateObject(wrappedValue: ListMembersViewModel(apiClient: apiClient, listID: list.id))
    }

    var body: some View {
        let request = viewModel.searchRequest
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, theme.spacing.contentHorizontalInset)
                .padding(.vertical, theme.spacing.s)
                .moroReadableColumn()
            ContentStateContainer(state: contentState) {
                if case .searching = viewModel.searchState {
                    ProgressView(MoroL10n.ListMembers.searching)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    accountList
                }
            }
        }
        .background(theme.colors.surfaceBase)
        .navigationTitle(MoroL10n.ListMembers.membersOf(list.title))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadInitial() }
        .task(id: request) { await viewModel.search(request) }
    }

    private var searchField: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityHidden(true)
            TextField(MoroL10n.ListMembers.searchFollowing, text: $viewModel.searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityIdentifier("listMembers.search")
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(minWidth: 36, minHeight: 44)
                }
                .accessibilityLabel(MoroL10n.NewConversation.clearSearch)
                .accessibilityIdentifier("listMembers.clear")
            }
        }
        .padding(.horizontal, theme.spacing.m)
        .frame(minHeight: 44)
        .background(theme.colors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private var contentState: ContentState {
        switch viewModel.loadingState {
        case .idle, .loading: return .loading(.list)
        case .failed where viewModel.members.isEmpty:
            return .error(ErrorStateSpec(title: MoroL10n.ListMembers.loadFailed,
                message: MoroL10n.ListMembers.toastLoadFailed, action: { Task { await viewModel.refresh() } }))
        default: break
        }
        switch viewModel.searchState {
        case .idle where viewModel.members.isEmpty:
            return .empty(EmptyStateSpec(icon: "person.2", title: MoroL10n.ListMembers.emptyTitle,
                message: MoroL10n.ListMembers.emptyMessage, actionTitle: MoroL10n.ListMembers.addMember,
                action: { searchFocused = true }))
        case .results(let accounts) where accounts.isEmpty:
            return .empty(EmptyStateSpec(icon: "person.crop.circle.badge.questionmark",
                title: MoroL10n.ListMembers.searchNoResultTitle, message: MoroL10n.ListMembers.searchNoResultMessage))
        case .failed(let message):
            return .error(ErrorStateSpec(title: MoroL10n.Search.errorSearchFailed,
                message: message, action: viewModel.retrySearch))
        default:
            return .loaded
        }
    }

    private var accountList: some View {
        let searching = !viewModel.searchRequest.query.isEmpty
        let accounts = if case .results(let accounts) = viewModel.searchState { accounts } else { viewModel.members }
        return List {
            if viewModel.loadingState == .failed {
                Button(MoroL10n.ListMembers.toastLoadFailed) { Task { await viewModel.refresh() } }
                    .font(theme.typography.caption)
            }
            ForEach(accounts) { account in
                accountRow(account, searching: searching)
                    .listRowBackground(theme.colors.surfaceBase)
            }
        }
        .listStyle(.plain)
        .moroReadableListMargins()
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await viewModel.refresh() }
    }

    private func accountRow(_ account: Account, searching: Bool) -> some View {
        let alreadyAdded = searching && viewModel.members.contains { $0.id == account.id }
        let failure = alreadyAdded ? nil : viewModel.mutationErrors[account.id]
        return VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(spacing: theme.spacing.m) {
                MoroAvatar(imageURL: account.avatarAnimatedURL, staticImageURL: account.avatarURL,
                    initials: account.displayNameInitials, seed: account.placeholderSeed, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    AccountDisplayNameView(account: account, typography: .bodyStrong,
                        textColor: theme.colors.textPrimary, lineLimit: 1)
                    Text(verbatim: "@\(account.acct)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: theme.spacing.s)
                if viewModel.mutatingAccountIDs.contains(account.id) {
                    ProgressView()
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(searching ? MoroL10n.ListMembers.add : MoroL10n.ListMembers.remove)
                        .accessibilityIdentifier("listMembers.pending.\(account.id)")
                } else if alreadyAdded {
                    Label(MoroL10n.ListMembers.added, systemImage: "checkmark")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityIdentifier("listMembers.added.\(account.id)")
                } else {
                    Button {
                        Task { await viewModel.setMembership(of: account, included: searching) }
                    } label: {
                        Group {
                            if searching || failure != nil {
                                Text(failure == nil ? MoroL10n.ListMembers.add : MoroL10n.ListMembers.retry)
                                    .font(theme.typography.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(theme.colors.themeTint.opacity(0.12), in: Capsule())
                            } else {
                                Image(systemName: "minus.circle")
                                    .font(.title3)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(searching ? theme.colors.themeTint : theme.colors.textSecondary)
                    .accessibilityLabel(failure != nil ? MoroL10n.ListMembers.retry
                        : searching ? MoroL10n.ListMembers.addMember : MoroL10n.ListMembers.removeAccessibility)
                    .accessibilityIdentifier("listMembers.\(searching ? "add" : "remove").\(account.id)")
                }
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.circle")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.error)
                    .accessibilityIdentifier("listMembers.error.\(account.id)")
            }
        }
        .padding(.vertical, 2)
    }
}

@MainActor
final class ListMembersViewModel: ObservableObject {
    nonisolated deinit {}

    enum LoadingState { case idle, loading, loaded, failed }
    enum SearchState {
        case idle, searching, results([Account]), failed(String)
    }

    struct SearchRequest: Equatable {
        let query: String
        let immediate: Bool
        private let id = UUID()
    }

    @Published private(set) var members: [Account] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var mutatingAccountIDs: Set<String> = []
    @Published private(set) var mutationErrors: [String: String] = [:]
    @Published private(set) var searchState: SearchState = .idle
    @Published private(set) var searchRequest = SearchRequest(query: "", immediate: false)
    @Published var searchQuery = "" {
        didSet {
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query != searchRequest.query else { return }
            searchState = query.isEmpty ? .idle : .searching
            searchRequest = SearchRequest(query: query, immediate: false)
        }
    }

    private let apiClient: MastodonAPI
    private let listID: String
    // Keep edits acknowledged by the server while a membership read is in flight.
    private var editsDuringRefresh: Set<String>?

    init(apiClient: MastodonAPI, listID: String) {
        self.apiClient = apiClient
        self.listID = listID
    }

    func loadInitial() async {
        guard loadingState == .idle else { return }
        await refresh()
    }

    func refresh() async {
        guard editsDuringRefresh == nil else { return }
        editsDuringRefresh = []
        defer { editsDuringRefresh = nil }
        if members.isEmpty { loadingState = .loading }
        do {
            // Mastodon uses limit=0 to return the complete membership, including beyond the first 80.
            let fetched = try await apiClient.fetchListAccounts(listID: listID, maxID: nil, sinceID: nil, limit: 0)
            let edited = editsDuringRefresh ?? []
            members = fetched.filter { !edited.contains($0.id) } + members.filter { edited.contains($0.id) }
            loadingState = .loaded
        } catch {
            if Task.isCancelled {
                if loadingState == .loading { loadingState = .idle }
            } else {
                loadingState = .failed
            }
        }
    }

    func retrySearch() {
        guard !searchRequest.query.isEmpty else { return }
        searchState = .searching
        searchRequest = SearchRequest(query: searchRequest.query, immediate: true)
    }

    func search(_ request: SearchRequest) async {
        guard !request.query.isEmpty, request == searchRequest else { return }
        do {
            if !request.immediate { try await Task.sleep(for: .milliseconds(300)) }
            try Task.checkCancellation()
            guard request == searchRequest else { return }
            let accounts = try await apiClient.searchFollowedAccounts(query: request.query, limit: 20)
            guard !Task.isCancelled, request == searchRequest else { return }
            searchState = .results(accounts)
        } catch {
            guard !Task.isCancelled, request == searchRequest else { return }
            searchState = .failed(error.localizedDescription)
        }
    }

    func setMembership(of account: Account, included: Bool) async {
        guard members.contains(where: { $0.id == account.id }) != included,
              mutatingAccountIDs.insert(account.id).inserted else { return }
        mutationErrors[account.id] = nil
        defer { mutatingAccountIDs.remove(account.id) }
        do {
            if included {
                try await apiClient.addAccountsToList(listID: listID, accountIDs: [account.id])
                if !members.contains(where: { $0.id == account.id }) { members.append(account) }
            } else {
                try await apiClient.removeAccountsFromList(listID: listID, accountIDs: [account.id])
                members.removeAll { $0.id == account.id }
            }
            editsDuringRefresh?.insert(account.id)
        } catch {
            mutationErrors[account.id] = included ? MoroL10n.ListMembers.toastAddFailed : MoroL10n.ListMembers.toastRemoveFailed
        }
    }
}
