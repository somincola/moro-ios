//
//  ListMembersView.swift
//  moro
//
//  Manage list members: view, search, add and remove accounts.
//

import SwiftUI
import Combine

struct ListMembersView: View {
    let list: MastodonList
    @Environment(\.moroTheme) private var theme
    @StateObject private var viewModel: ListMembersViewModel
    @State private var showPicker = false

    init(list: MastodonList, apiClient: MastodonAPI) {
        self.list = list
        _viewModel = StateObject(
            wrappedValue: ListMembersViewModel(apiClient: apiClient, listID: list.id)
        )
    }

    var body: some View {
        NavigationStack {
            ContentStateContainer(state: contentState) {
                memberList
            }
            .navigationTitle(MoroL10n.ListMembers.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel(MoroL10n.ListMembers.addMember)
                }
            }
            .background(theme.colors.background.ignoresSafeArea())
        }
        .task {
            await viewModel.loadInitial()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showPicker) {
            ListMemberPickerSheet(
                viewModel: viewModel,
                listTitle: list.title,
                onClose: {
                    showPicker = false
                }
            )
        }
    }

    private var contentState: ContentState {
        if viewModel.members.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.list)
        }
        if viewModel.members.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.ListMembers.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.ListMembers.retry,
                    action: {
                        Task { await viewModel.refresh() }
                    }
                )
            )
        }
        if viewModel.members.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "person.2",
                    title: MoroL10n.ListMembers.emptyTitle,
                    message: MoroL10n.ListMembers.emptyMessage,
                    actionTitle: MoroL10n.ListMembers.addMember,
                    action: {
                        showPicker = true
                    }
                )
            )
        }
        return .loaded
    }

    @ViewBuilder
    private var memberList: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing.s) {
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
                }

                ForEach(viewModel.members) { account in
                    memberRow(account)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.removeAccount(account) }
                            } label: {
                                Label(MoroL10n.ListMembers.remove, systemImage: "person.crop.circle.badge.minus")
                            }
                            .disabled(viewModel.isMutating(accountID: account.id))
                        }
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
            .moroReadableColumn()
        }
    }

    @ViewBuilder
    private func memberRow(_ account: Account) -> some View {
        HStack(spacing: theme.spacing.m) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials, seed: account.placeholderSeed,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                AccountDisplayNameView(
                    account: account,
                    typography: .body,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 1
                )
                Text("@\(account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if viewModel.isMutating(accountID: account.id) {
                ProgressView()
                    .scaleEffect(0.9)
            } else {
                Button {
                    Task { await viewModel.removeAccount(account) }
                } label: {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .moroScaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(theme.colors.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.ListMembers.removeAccessibility)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surfaceBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }
}

private struct ListMemberPickerSheet: View {
    @Environment(\.moroTheme) private var theme
    @ObservedObject var viewModel: ListMembersViewModel

    let listTitle: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: theme.spacing.m) {
                HStack(spacing: theme.spacing.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.colors.textSecondary)
                    TextField(MoroL10n.ListMembers.searchPlaceholder, text: $viewModel.searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, theme.spacing.s)
                .background(theme.colors.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )

                if let message = viewModel.searchErrorMessage {
                    HStack(spacing: theme.spacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.colors.error)
                        Text(message)
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
                }

                pickerContent
            }
            .padding(theme.spacing.m)
            .navigationTitle(MoroL10n.ListMembers.addToList(listTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    MoroToolbarButton(MoroL10n.ListMembers.done, kind: .confirm) {
                        onClose()
                    }
                }
            }
        }
        .onDisappear {
            viewModel.resetSearch()
        }
        .moroTheme(MoroTheme())
    }

    @ViewBuilder
    private var pickerContent: some View {
        let trimmedQuery = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.count < 2 {
            infoPlaceholder(
                icon: "text.magnifyingglass",
                title: MoroL10n.ListMembers.searchEmptyTitle,
                message: MoroL10n.ListMembers.searchEmptyMessage
            )
        } else if viewModel.isSearching {
            VStack(spacing: theme.spacing.s) {
                ProgressView()
                Text(MoroL10n.ListMembers.searching)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.searchResults.isEmpty {
            infoPlaceholder(
                icon: "person.crop.circle.badge.questionmark",
                title: MoroL10n.ListMembers.searchNoResultTitle,
                message: MoroL10n.ListMembers.searchNoResultMessage
            )
        } else {
            ScrollView {
                LazyVStack(spacing: theme.spacing.s) {
                    ForEach(viewModel.searchResults) { account in
                        searchResultRow(account)
                    }
                }
                .padding(.bottom, theme.spacing.m)
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ account: Account) -> some View {
        HStack(spacing: theme.spacing.m) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials, seed: account.placeholderSeed,
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                AccountDisplayNameView(
                    account: account,
                    typography: .body,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 1
                )
                Text("@\(account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if viewModel.isMutating(accountID: account.id) {
                ProgressView()
                    .scaleEffect(0.9)
            } else {
                Button {
                    Task { await viewModel.addAccount(account) }
                } label: {
                    Text(MoroL10n.ListMembers.add)
                        .font(theme.typography.caption.bold())
                        .foregroundStyle(theme.colors.primary600)
                        .padding(.horizontal, theme.spacing.s)
                        .padding(.vertical, 6)
                        .background(theme.colors.primary50)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surfaceBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoPlaceholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: theme.spacing.s) {
            Image(systemName: icon)
                .moroScaledFont(size: 26, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
            Text(title)
                .font(theme.typography.subtitle)
                .foregroundStyle(theme.colors.textPrimary)
            Text(message)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(theme.spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }
}

@MainActor
final class ListMembersViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(Error)
    }

    @Published private(set) var members: [Account] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var transientErrorMessage: String?

    @Published var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var searchResults: [Account] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchErrorMessage: String?
    @Published private(set) var mutatingAccountIDs: Set<String> = []

    private let apiClient: MastodonAPI
    private let listID: String
    private var searchTask: Task<Void, Never>?

    init(apiClient: MastodonAPI, listID: String) {
        self.apiClient = apiClient
        self.listID = listID
    }

    deinit {
        searchTask?.cancel()
    }

    func loadInitial() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading
        await refresh()
    }

    func refresh() async {
        do {
            members = try await apiClient.fetchListAccounts(
                listID: listID,
                maxID: nil,
                sinceID: nil,
                limit: 80
            )
            loadingState = .loaded
            transientErrorMessage = nil
            filterSearchResultsAgainstMembers()
        } catch {
            if members.isEmpty {
                loadingState = .error(error)
            } else {
                loadingState = .loaded
            }
            transientErrorMessage = MoroL10n.ListMembers.toastLoadFailed
        }
    }

    func addAccount(_ account: Account) async {
        guard !mutatingAccountIDs.contains(account.id) else { return }
        mutatingAccountIDs.insert(account.id)
        defer { mutatingAccountIDs.remove(account.id) }

        do {
            try await apiClient.addAccountsToList(listID: listID, accountIDs: [account.id])
            if members.contains(where: { $0.id == account.id }) == false {
                members.append(account)
            }
            filterSearchResultsAgainstMembers()
            transientErrorMessage = nil
            searchErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.ListMembers.toastAdded)
        } catch {
            searchErrorMessage = MoroL10n.ListMembers.toastAddFailed
            AppFeedbackCenter.shared.showError(MoroL10n.ListMembers.toastAddFailedShort)
        }
    }

    func removeAccount(_ account: Account) async {
        guard !mutatingAccountIDs.contains(account.id) else { return }
        mutatingAccountIDs.insert(account.id)
        defer { mutatingAccountIDs.remove(account.id) }

        do {
            try await apiClient.removeAccountsFromList(listID: listID, accountIDs: [account.id])
            members.removeAll { $0.id == account.id }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.ListMembers.toastRemoved)
            scheduleSearch(immediate: true)
        } catch {
            transientErrorMessage = MoroL10n.ListMembers.toastRemoveFailed
            AppFeedbackCenter.shared.showError(MoroL10n.ListMembers.toastRemoveFailedShort)
        }
    }

    func isMutating(accountID: String) -> Bool {
        mutatingAccountIDs.contains(accountID)
    }

    func resetSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = []
        isSearching = false
        searchErrorMessage = nil
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchErrorMessage = nil

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            await self.performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }

        do {
            let result = try await apiClient.search(
                query: query,
                type: .accounts,
                resolve: true,
                limit: 20,
                offset: nil
            )
            if query != searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                return
            }
            searchResults = result.accounts
            filterSearchResultsAgainstMembers()
        } catch {
            if query != searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                return
            }
            searchResults = []
            searchErrorMessage = MoroL10n.ListMembers.toastSearchFailed
        }
    }

    private func filterSearchResultsAgainstMembers() {
        let memberIDs = Set(members.map(\.id))
        searchResults = searchResults.filter { memberIDs.contains($0.id) == false }
    }
}
