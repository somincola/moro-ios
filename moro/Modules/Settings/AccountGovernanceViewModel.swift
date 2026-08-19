//
//  AccountGovernanceViewModel.swift
//  moro
//
//  ViewModel for muted/blocked account management pages.
//

import Combine
import Foundation

enum AccountGovernanceKind {
    case muted
    case blocked

    var navigationTitle: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteNavTitle
        case .blocked: return MoroL10n.Governance.blockNavTitle
        }
    }

    var sectionTitle: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteTitle
        case .blocked: return MoroL10n.Governance.blockTitle
        }
    }

    var emptyTitle: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteEmptyTitle
        case .blocked: return MoroL10n.Governance.blockEmptyTitle
        }
    }

    var emptyMessage: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteEmptyMessage
        case .blocked: return MoroL10n.Governance.blockEmptyMessage
        }
    }

    var releaseActionTitle: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteRelease
        case .blocked: return MoroL10n.Governance.blockRelease
        }
    }

    var footerText: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteFooter
        case .blocked: return MoroL10n.Governance.blockFooter
        }
    }

    var loadingFailureMessage: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteLoadFailed
        case .blocked: return MoroL10n.Governance.blockLoadFailed
        }
    }

    var releaseSuccessMessage: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteReleased
        case .blocked: return MoroL10n.Governance.blockReleased
        }
    }

    var releaseFailureMessage: String {
        switch self {
        case .muted: return MoroL10n.Governance.muteReleaseFailed
        case .blocked: return MoroL10n.Governance.blockReleaseFailed
        }
    }
}

@MainActor
final class AccountGovernanceViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(Error)
    }

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private var mutatingAccountIDs: Set<String> = []
    @Published var transientErrorMessage: String?

    let kind: AccountGovernanceKind

    private let apiClient: MastodonAPI
    init(kind: AccountGovernanceKind, apiClient: MastodonAPI) {
        self.kind = kind
        self.apiClient = apiClient
    }

    func loadInitial() async {
        guard case .idle = loadingState else { return }
        await load(showLoading: true)
    }

    func refresh() async {
        await load(showLoading: accounts.isEmpty)
    }

    func isMutating(accountID: String) -> Bool {
        mutatingAccountIDs.contains(accountID)
    }

    func release(_ account: Account) async {
        guard !isMutating(accountID: account.id) else { return }
        mutatingAccountIDs.insert(account.id)
        defer { mutatingAccountIDs.remove(account.id) }

        do {
            switch kind {
            case .muted:
                _ = try await apiClient.unmuteAccount(id: account.id)
            case .blocked:
                _ = try await apiClient.unblockAccount(id: account.id)
            }

            accounts.removeAll { $0.id == account.id }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(kind.releaseSuccessMessage)
        } catch {
            transientErrorMessage = kind == .muted
                ? MoroL10n.Governance.muteReleaseFailedDetail
                : MoroL10n.Governance.blockReleaseFailedDetail
            AppFeedbackCenter.shared.showError(kind.releaseFailureMessage)
        }
    }

    private func load(showLoading: Bool) async {
        if showLoading {
            loadingState = .loading
        }

        do {
            switch kind {
            case .muted:
                accounts = try await apiClient.fetchMutedAccounts(
                    maxID: nil,
                    sinceID: nil,
                    limit: 200
                )
            case .blocked:
                accounts = try await apiClient.fetchBlockedAccounts(
                    maxID: nil,
                    sinceID: nil,
                    limit: 200
                )
            }

            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            if accounts.isEmpty {
                loadingState = .error(error)
            } else {
                loadingState = .loaded
            }
            transientErrorMessage = kind.loadingFailureMessage
        }
    }
}
