//
//  AccountReportViewModel.swift
//  moro
//
//  ViewModel for account-level report flow.
//

import Foundation
import Combine

@MainActor
final class AccountReportViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let apiClient: MastodonAPI
    private let account: Account

    @Published var selectedReason: ReportReason?
    @Published var customComment: String = ""
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String?
    @Published var isSubmitted: Bool = false

    var accountUsername: String {
        account.username
    }

    var canSubmit: Bool {
        selectedReason != nil && !isSubmitting
    }

    init(apiClient: MastodonAPI, account: Account) {
        self.apiClient = apiClient
        self.account = account
    }

    func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var fullComment = selectedReason?.title ?? ""
        let trimmedComment = customComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty {
            fullComment += ": \(trimmedComment)"
        }

        do {
            _ = try await apiClient.report(
                accountID: account.id,
                statusIDs: [],
                comment: fullComment
            )
            AppFeedbackCenter.shared.showSuccess(MoroL10n.AccountReportVM.submitted)
            isSubmitted = true
        } catch {
            errorMessage = userFriendlySubmitError(error)
            AppFeedbackCenter.shared.showError(MoroL10n.AccountReportVM.submitFailed)
        }
    }

    private func userFriendlySubmitError(_ error: Error) -> String {
        let raw = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        if raw.lowercased().contains("network") || raw.lowercased().contains("offline") {
            return MoroL10n.AccountReportVM.networkError
        }
        return MoroL10n.AccountReportVM.submitFailedDetail(raw)
    }
}
