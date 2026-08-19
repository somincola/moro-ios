//
//  ReportViewModel.swift
//  moro
//
//  ViewModel for multi-step report flow.
//

import Foundation
import Combine

// MARK: - Report Step

enum ReportStep: Int, CaseIterable {
    case reason = 0
    case selectPosts = 1
    case submitting = 2
}

// MARK: - Report Reason

enum ReportReason: String, CaseIterable, Identifiable {
    case offensive
    case spam
    case illegal
    case violation
    case other
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .offensive: return MoroL10n.Report.reasonOffensive
        case .spam: return MoroL10n.Report.reasonSpam
        case .illegal: return MoroL10n.Report.reasonIllegal
        case .violation: return MoroL10n.Report.reasonViolation
        case .other: return MoroL10n.Report.reasonOther
        }
    }

    var description: String {
        switch self {
        case .offensive: return MoroL10n.Report.reasonOffensiveDesc
        case .spam: return MoroL10n.Report.reasonSpamDesc
        case .illegal: return MoroL10n.Report.reasonIllegalDesc
        case .violation: return MoroL10n.Report.reasonViolationDesc
        case .other: return MoroL10n.Report.reasonOtherDesc
        }
    }
}

// MARK: - ReportViewModel

@MainActor
class ReportViewModel: ObservableObject {
    enum StepErrorContext {
        case loadStatuses
        case loadMore
        case submit
    }

    struct StepErrorState {
        let message: String
        let context: StepErrorContext
    }

    private let apiClient: MastodonAPI
    private let initialStatus: Status
    private let accountID: String
    
    // MARK: - Step Management
    
    @Published var currentStep: ReportStep = .reason
    
    // MARK: - Step 1: Reason Selection
    
    @Published var selectedReason: ReportReason?
    @Published var customComment: String = ""
    
    // MARK: - Step 2: Post Selection
    
    @Published var selectedStatusIDs: Set<String> = []
    @Published var userStatuses: [Status] = []
    @Published var isLoadingStatuses: Bool = false
    @Published var hasMoreStatuses: Bool = true
    private var maxStatusID: String?
    
    // MARK: - Submission
    
    @Published var isSubmitting: Bool = false
    @Published var error: Error?
    @Published var isSubmitted: Bool = false
    @Published var stepError: StepErrorState?
    
    // MARK: - Computed Properties
    
    var canProceedToNextStep: Bool {
        switch currentStep {
        case .reason:
            return selectedReason != nil
        case .selectPosts:
            return !selectedStatusIDs.isEmpty
        case .submitting:
            return false
        }
    }
    
    var accountUsername: String {
        initialStatus.account.username
    }
    
    // MARK: - Initialization
    
    init(apiClient: MastodonAPI, status: Status) {
        self.apiClient = apiClient
        self.initialStatus = status
        self.accountID = status.account.id
        // Auto-select the triggering status
        self.selectedStatusIDs = [status.id]
    }
    
    // MARK: - Navigation
    
    func goToNextStep() {
        switch currentStep {
        case .reason:
            stepError = nil
            currentStep = .selectPosts
            // Load user statuses when entering step 2
            if userStatuses.isEmpty {
                Task {
                    await loadUserStatuses()
                }
            }
        case .selectPosts:
            Task {
                await submitReport()
            }
        case .submitting:
            break
        }
    }
    
    func goToPreviousStep() {
        switch currentStep {
        case .reason:
            break // Can't go back from first step
        case .selectPosts:
            stepError = nil
            currentStep = .reason
        case .submitting:
            break // Can't go back while submitting
        }
    }
    
    // MARK: - Status Selection
    
    func toggleStatusSelection(_ statusID: String) {
        if selectedStatusIDs.contains(statusID) {
            selectedStatusIDs.remove(statusID)
        } else {
            selectedStatusIDs.insert(statusID)
        }
    }
    
    func isStatusSelected(_ statusID: String) -> Bool {
        selectedStatusIDs.contains(statusID)
    }
    
    // MARK: - Load User Statuses
    
    func loadUserStatuses() async {
        guard !isLoadingStatuses else { return }
        
        isLoadingStatuses = true
        defer { isLoadingStatuses = false }
        
        do {
            let statuses = try await apiClient.fetchAccountStatuses(
                id: accountID,
                maxID: nil,
                sinceID: nil,
                limit: 20,
                excludeReplies: false,
                excludeReblogs: false,
                onlyMedia: false,
                pinned: false
            )
            
            userStatuses = statuses
            maxStatusID = statuses.last?.id
            hasMoreStatuses = statuses.count >= 20
            
            // Ensure initial status is in the list (might be at top)
            if !userStatuses.contains(where: { $0.id == initialStatus.id }) {
                userStatuses.insert(initialStatus, at: 0)
            }
            stepError = nil
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.Report.errorLoadPostsShort)
            AppLogger.error("Failed to load user statuses: \(error)")
            stepError = StepErrorState(
                message: MoroL10n.Report.errorLoadPosts,
                context: .loadStatuses
            )
            // Still show the initial status
            if userStatuses.isEmpty {
                userStatuses = [initialStatus]
            }
        }
    }
    
    func loadMoreStatuses() async {
        guard !isLoadingStatuses, hasMoreStatuses, let maxID = maxStatusID else { return }
        
        isLoadingStatuses = true
        defer { isLoadingStatuses = false }
        
        do {
            let statuses = try await apiClient.fetchAccountStatuses(
                id: accountID,
                maxID: maxID,
                sinceID: nil,
                limit: 20,
                excludeReplies: false,
                excludeReblogs: false,
                onlyMedia: false,
                pinned: false
            )
            
            userStatuses.append(contentsOf: statuses)
            maxStatusID = statuses.last?.id
            hasMoreStatuses = statuses.count >= 20
            stepError = nil
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.Report.errorLoadMoreShort)
            AppLogger.error("Failed to load more statuses: \(error)")
            stepError = StepErrorState(
                message: MoroL10n.Report.errorLoadMore,
                context: .loadMore
            )
        }
    }
    
    // MARK: - Submit Report
    
    func submitReport() async {
        guard canProceedToNextStep else { return }
        
        currentStep = .submitting
        isSubmitting = true
        stepError = nil
        defer { isSubmitting = false }
        
        // Build comment from reason + custom comment
        var fullComment = selectedReason?.title ?? ""
        if !customComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullComment += ": " + customComment.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        do {
            _ = try await apiClient.report(
                accountID: accountID,
                statusIDs: Array(selectedStatusIDs),
                comment: fullComment
            )
            AppLogger.debug("Report submitted successfully")
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Report.successSubmitted)
            isSubmitted = true
        } catch {
            self.error = error
            AppFeedbackCenter.shared.showError(MoroL10n.Report.errorSubmitShort)
            AppLogger.error("Failed to submit report: \(error)")
            stepError = StepErrorState(
                message: MoroL10n.Report.errorSubmit,
                context: .submit
            )
            currentStep = .selectPosts // Go back to allow retry
        }
    }

    var stepErrorActionTitle: String {
        guard let stepError else { return MoroL10n.Report.retry }
        switch stepError.context {
        case .loadStatuses:
            return MoroL10n.Report.retryLoadPosts
        case .loadMore:
            return MoroL10n.Report.retryLoadMore
        case .submit:
            return MoroL10n.Report.retrySubmit
        }
    }

    func retryStepErrorAction() {
        guard let stepError else { return }
        self.stepError = nil

        switch stepError.context {
        case .loadStatuses:
            Task {
                await reloadUserStatuses()
            }
        case .loadMore:
            Task {
                await loadMoreStatuses()
            }
        case .submit:
            Task {
                await submitReport()
            }
        }
    }

    private func reloadUserStatuses() async {
        maxStatusID = nil
        hasMoreStatuses = true
        userStatuses = []
        await loadUserStatuses()
    }
}
