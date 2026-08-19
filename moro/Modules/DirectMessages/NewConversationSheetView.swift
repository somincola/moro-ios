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
                headerCard

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
                ToolbarItem(placement: .navigationBarLeading) {
                    MoroNavigationControlButton(kind: .close) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: viewModel.query) { _, _ in
            viewModel.scheduleSearch()
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            ZStack {
                Circle()
                    .fill(theme.colors.primary500.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .moroScaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(theme.colors.primary500)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(MoroL10n.NewConversation.selectHint)
                    .font(theme.typography.bodyStrong)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(MoroL10n.NewConversation.selectDesc)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(theme.spacing.s)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .moroScaledFont(size: 13, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)

            TextField(MoroL10n.NewConversation.searchPlaceholder, text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    viewModel.searchNow()
                }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.scheduleSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .moroScaledFont(size: 14)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
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
            LazyVStack(alignment: .leading, spacing: theme.spacing.xs) {
                HStack(spacing: 8) {
                    Text(resultSectionTitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer()
                    Text("\(viewModel.displayAccounts.count)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

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
                }
            }
            .padding(.bottom, theme.spacing.s)
        }
    }

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials,
                size: 42
            )

            VStack(alignment: .leading, spacing: 3) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 1
                )

                Text("@\(account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "bubble.right")
                .moroScaledFont(size: 12, weight: .semibold)
                .foregroundStyle(theme.colors.primary500.opacity(0.85))
                .padding(8)
                .background(
                    Circle()
                        .fill(theme.colors.primary500.opacity(0.12))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
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
