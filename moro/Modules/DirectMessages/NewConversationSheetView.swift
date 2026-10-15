//
//  NewConversationSheetView.swift
//  moro
//
//  Account picker for starting a new direct-message conversation.
//

import SwiftUI
import Combine

@MainActor
final class NewConversationViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published var query: String = ""
    @Published private(set) var results: [Account] = []
    @Published private(set) var loadingState: LoadingState = .idle

    private let apiClient: MastodonAPI
    private let currentUserID: String?
    private let recentAccounts: [Account]
    private var searchTask: Task<Void, Never>?

    init(apiClient: MastodonAPI, recentAccounts: [Account], currentUserID: String?) {
        self.apiClient = apiClient
        self.currentUserID = currentUserID
        self.recentAccounts = Self.uniqueAccounts(
            from: recentAccounts,
            excluding: currentUserID
        )
        self.results = self.recentAccounts
    }

    deinit {
        searchTask?.cancel()
    }

    var displayAccounts: [Account] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? recentAccounts : results
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            loadingState = .loaded
            results = recentAccounts
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.searchAccounts(query: trimmed)
        }
    }

    func searchNow() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            loadingState = .loaded
            results = recentAccounts
            return
        }

        searchTask = Task { [weak self] in
            await self?.searchAccounts(query: trimmed)
        }
    }

    private func searchAccounts(query: String) async {
        loadingState = .loading
        do {
            let searchResults = try await apiClient.search(
                query: query,
                type: .accounts,
                resolve: true,
                limit: 20,
                offset: nil
            )
            let filtered = Self.uniqueAccounts(
                from: searchResults.accounts,
                excluding: currentUserID
            )
            results = filtered
            loadingState = .loaded
        } catch {
            results = []
            loadingState = .error(MoroL10n.NewConversation.searchFailed)
        }
    }

    private static func uniqueAccounts(from accounts: [Account], excluding accountID: String?) -> [Account] {
        var seen = Set<String>()
        var unique: [Account] = []

        for account in accounts {
            if let accountID, account.id == accountID {
                continue
            }
            if seen.insert(account.id).inserted {
                unique.append(account)
            }
        }
        return unique
    }
}

struct NewConversationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: NewConversationViewModel

    let onSelectAccount: (Account) -> Void

    init(
        apiClient: MastodonAPI,
        recentAccounts: [Account],
        currentUserID: String?,
        onSelectAccount: @escaping (Account) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: NewConversationViewModel(
                apiClient: apiClient,
                recentAccounts: recentAccounts,
                currentUserID: currentUserID
            )
        )
        self.onSelectAccount = onSelectAccount
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: theme.spacing.m) {
                searchField

                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.top, theme.spacing.s)
            .background(theme.colors.background)
            .navigationTitle(MoroL10n.NewConversation.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MoroL10n.Common.cancel) {
                        dismiss()
                    }
                    .accessibilityIdentifier("newConversation.cancel")
                }
            }
        }
        .onChange(of: viewModel.query) { _, _ in
            viewModel.scheduleSearch()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .moroScaledFont(size: 13, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)

            TextField(MoroL10n.NewConversation.searchPlaceholder, text: $viewModel.query)
                .font(theme.typography.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    viewModel.searchNow()
                }
                .accessibilityIdentifier("newConversation.search")
                .padding(.vertical, 8)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.scheduleSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .moroScaledFont(size: 14)
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.NewConversation.clearSearch)
                .accessibilityIdentifier("newConversation.clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        )
    }

    private var resultSectionTitle: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MoroL10n.NewConversation.recentContacts : MoroL10n.NewConversation.searchResults
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.loadingState {
        case .idle, .loaded:
            if viewModel.displayAccounts.isEmpty {
                emptyStateView
            } else {
                accountList
            }
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text(MoroL10n.NewConversation.searching)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, theme.spacing.l)
        case .error(let message):
            VStack(spacing: theme.spacing.m) {
                InlineFeedbackCard(
                    kind: .error,
                    message: message,
                    actionTitle: MoroL10n.NewConversation.retry,
                    action: { viewModel.searchNow() }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var accountList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(resultSectionTitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, theme.spacing.s)

                ForEach(viewModel.displayAccounts) { account in
                    Button {
                        dismiss()
                        DispatchQueue.main.async {
                            onSelectAccount(account)
                        }
                    } label: {
                        accountRow(account)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("newConversation.account.\(account.id)")

                    if account.id != viewModel.displayAccounts.last?.id {
                        MoroDivider()
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.bottom, theme.spacing.s)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials, seed: account.placeholderSeed,
                size: 42
            )

            VStack(alignment: .leading, spacing: 3) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: theme.colors.textPrimary,
                    lineLimit: dynamicTypeSize.isAccessibilitySize ? 3 : 1
                )

                Text("@\(account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyStateView: some View {
        VStack(spacing: theme.spacing.s) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .moroScaledFont(size: 36, weight: .medium)
                .foregroundStyle(theme.colors.textTertiary)
            Text(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MoroL10n.NewConversation.emptyRecent : MoroL10n.NewConversation.emptySearch)
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.textPrimary)
            Text(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MoroL10n.NewConversation.emptyRecentHint : MoroL10n.NewConversation.emptySearchHint)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
