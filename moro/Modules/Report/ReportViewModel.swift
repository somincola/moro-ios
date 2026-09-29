import Combine
import Foundation

enum ReportStep: Hashable {
    case reason, rules, selectPosts, comment, result
}

enum ReportReason: String, CaseIterable, Identifiable {
    case dislike, spam, violation, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dislike: MoroL10n.Report.reasonOffensive
        case .spam: MoroL10n.Report.reasonSpam
        case .violation: MoroL10n.Report.reasonViolation
        case .other: MoroL10n.Report.reasonOther
        }
    }

    var description: String {
        switch self {
        case .dislike: MoroL10n.Report.reasonOffensiveDesc
        case .spam: MoroL10n.Report.reasonSpamDesc
        case .violation: MoroL10n.Report.reasonViolationDesc
        case .other: MoroL10n.Report.reasonOtherDesc
        }
    }

    var category: ReportRequest.Category? {
        switch self {
        case .dislike: nil
        case .spam: .spam
        case .violation: .violation
        case .other: .other
        }
    }
}

@MainActor
final class ReportViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum AccountAction: String, Identifiable {
        case unfollow, mute, block
        var id: String { rawValue }
    }

    enum StepErrorContext: Equatable {
        case loadRules, loadStatuses, loadMore, submit, loadRelationship, accountAction
    }

    struct StepErrorState {
        let message: String
        let context: StepErrorContext
    }

    static let commentLimit = 1_000
    let account: Account
    private let apiClient: MastodonAPI
    private let feedCoordinator: FeedCoordinator
    private var didLoadRules = false
    private var didLoadStatuses = false
    private var maxStatusID: String?

    @Published private(set) var currentStep: ReportStep = .reason
    @Published var selectedReason: ReportReason?
    @Published var customComment = ""
    @Published private(set) var rules: [MastodonInstanceRule] = []
    @Published private(set) var selectedRuleIDs: Set<String> = []
    @Published private(set) var isLoadingRules = false
    @Published private(set) var selectedStatusIDs: Set<String> = []
    @Published private(set) var userStatuses: [Status] = []
    @Published private(set) var isLoadingStatuses = false
    @Published private(set) var hasMoreStatuses = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var isSubmitted = false
    @Published private(set) var stepError: StepErrorState?
    @Published private(set) var relationship: Relationship?
    @Published private(set) var isLoadingRelationship = false
    @Published private(set) var activeAccountAction: AccountAction?
    @Published private(set) var hasUnfollowed = false

    var accountUsername: String { account.username }
    var comment: String { customComment.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBusy: Bool { isSubmitting || activeAccountAction != nil }
    var hasValidRules: Bool {
        !selectedRuleIDs.isEmpty && selectedRuleIDs.isSubset(of: Set(rules.map(\.id)))
    }
    var canProceedToNextStep: Bool {
        guard !isBusy else { return false }
        switch currentStep {
        case .reason: return selectedReason != nil
        case .rules: return !isLoadingRules && hasValidRules
        case .selectPosts: return true
        case .comment:
            return selectedReason?.category != nil && comment.count <= Self.commentLimit
                && (selectedReason != .violation || hasValidRules)
        case .result: return false
        }
    }

    init(
        apiClient: MastodonAPI, account: Account, status: Status? = nil,
        feedCoordinator: FeedCoordinator = .shared
    ) {
        self.apiClient = apiClient
        self.account = account
        self.feedCoordinator = feedCoordinator
        if let status = status?.displayStatus, status.account.id == account.id {
            userStatuses = [status]
            selectedStatusIDs = [status.id]
        }
    }

    convenience init(apiClient: MastodonAPI, status: Status, feedCoordinator: FeedCoordinator = .shared) {
        let original = status.displayStatus
        self.init(
            apiClient: apiClient, account: original.account, status: original,
            feedCoordinator: feedCoordinator)
    }

    func goToNextStep() {
        guard canProceedToNextStep else { return }
        stepError = nil
        switch currentStep {
        case .reason:
            switch selectedReason {
            case .dislike: currentStep = .result
            case .violation: currentStep = .rules
            case .spam, .other: currentStep = .selectPosts
            case nil: break
            }
        case .rules: currentStep = .selectPosts
        case .selectPosts: currentStep = .comment
        case .comment, .result: break
        }
    }

    func goToPreviousStep() {
        guard !isBusy else { return }
        stepError = nil
        switch currentStep {
        case .rules: currentStep = .reason
        case .selectPosts: currentStep = selectedReason == .violation ? .rules : .reason
        case .comment: currentStep = .selectPosts
        case .result where !isSubmitted: currentStep = .reason
        case .reason, .result: break
        }
    }

    func prepareCurrentStep() async {
        switch currentStep {
        case .rules where !didLoadRules: await loadRules()
        case .selectPosts where !didLoadStatuses: await loadUserStatuses()
        case .result where relationship == nil: await loadRelationship()
        default: break
        }
    }

    func toggleRuleSelection(_ id: String) {
        guard !isBusy, rules.contains(where: { $0.id == id }) else { return }
        if !selectedRuleIDs.insert(id).inserted { selectedRuleIDs.remove(id) }
    }

    func toggleStatusSelection(_ id: String) {
        guard !isBusy, userStatuses.contains(where: { $0.id == id }) else { return }
        if !selectedStatusIDs.insert(id).inserted { selectedStatusIDs.remove(id) }
    }

    func loadRules() async {
        guard !isLoadingRules else { return }
        let requestedStep = currentStep
        isLoadingRules = true
        stepError = nil
        defer { isLoadingRules = false }
        do {
            // Report rule IDs belong to the signed-in instance, including reports of remote accounts.
            let instance = try await apiClient.fetchInstance()
            try Task.checkCancellation()
            rules = instance.rules ?? []
            selectedRuleIDs.formIntersection(rules.map(\.id))
            didLoadRules = true
        } catch {
            guard !Task.isCancelled, currentStep == requestedStep else { return }
            stepError = .init(message: MoroL10n.Report.errorLoadRules, context: .loadRules)
        }
    }

    func loadUserStatuses(loadMore: Bool = false) async {
        guard !isLoadingStatuses, !loadMore || (hasMoreStatuses && maxStatusID != nil) else { return }
        let requestedStep = currentStep
        isLoadingStatuses = true
        stepError = nil
        defer { isLoadingStatuses = false }
        let cursor = loadMore ? maxStatusID : nil
        do {
            let statuses = try await apiClient.fetchAccountStatuses(
                id: account.id, maxID: cursor, sinceID: nil, limit: 20,
                excludeReplies: false, excludeReblogs: true, onlyMedia: false, pinned: false
            )
            try Task.checkCancellation()
            var knownIDs = Set(userStatuses.map(\.id))
            userStatuses += statuses.filter {
                $0.reblog == nil && $0.account.id == account.id && knownIDs.insert($0.id).inserted
            }
            maxStatusID = statuses.last?.id
            hasMoreStatuses = statuses.count >= 20 && maxStatusID != cursor
            didLoadStatuses = true
        } catch {
            guard !Task.isCancelled, currentStep == requestedStep else { return }
            stepError = .init(
                message: loadMore ? MoroL10n.Report.errorLoadMore : MoroL10n.Report.errorLoadPosts,
                context: loadMore ? .loadMore : .loadStatuses
            )
        }
    }

    func submitReport() async {
        guard currentStep == .comment, canProceedToNextStep,
            let category = selectedReason?.category
        else { return }
        isSubmitting = true
        stepError = nil
        defer { isSubmitting = false }
        let request = ReportRequest(
            accountID: account.id,
            statusIDs: selectedStatusIDs.sorted(),
            comment: comment,
            category: category,
            ruleIDs: category == .violation ? selectedRuleIDs.sorted() : nil
        )
        do {
            _ = try await apiClient.report(request)
            isSubmitted = true
            currentStep = .result
        } catch {
            // Keep the draft and stay on the final step so retry cannot lose selections or text.
            stepError = .init(message: MoroL10n.Report.errorSubmit, context: .submit)
        }
    }

    func loadRelationship() async {
        guard !isLoadingRelationship, activeAccountAction == nil else { return }
        let requestedStep = currentStep
        isLoadingRelationship = true
        stepError = nil
        defer { isLoadingRelationship = false }
        do {
            let relationships = try await apiClient.fetchRelationships(accountIDs: [account.id])
            try Task.checkCancellation()
            guard let relationship = relationships.first(where: { $0.id == account.id }) else {
                stepError = .init(message: MoroL10n.Report.errorLoadRelationship, context: .loadRelationship)
                return
            }
            self.relationship = relationship
        } catch {
            guard !Task.isCancelled, currentStep == requestedStep else { return }
            stepError = .init(message: MoroL10n.Report.errorLoadRelationship, context: .loadRelationship)
        }
    }

    func isActionCompleted(_ action: AccountAction) -> Bool {
        guard let relationship else { return false }
        switch action {
        case .unfollow: return !relationship.following && !relationship.requested
        case .mute: return relationship.muting
        case .block: return relationship.blocking
        }
    }

    func performAccountAction(_ action: AccountAction) async {
        guard currentStep == .result, relationship != nil, !isBusy,
            !isLoadingRelationship, !isActionCompleted(action)
        else { return }
        activeAccountAction = action
        stepError = nil
        defer { activeAccountAction = nil }
        do {
            let updated: Relationship
            switch action {
            case .unfollow: updated = try await apiClient.unfollowAccount(id: account.id)
            case .mute: updated = try await apiClient.muteAccount(id: account.id)
            case .block: updated = try await apiClient.blockAccount(id: account.id)
            }
            relationship = updated
            if action == .unfollow { hasUnfollowed = !updated.following && !updated.requested }
            feedCoordinator.publishUpdate(.relationship(updated))
        } catch {
            stepError = .init(message: MoroL10n.Report.errorAccountAction, context: .accountAction)
        }
    }

    func retryStepErrorAction() async {
        guard let context = stepError?.context, !isBusy else { return }
        switch context {
        case .loadRules: await loadRules()
        case .loadStatuses: await loadUserStatuses()
        case .loadMore: await loadUserStatuses(loadMore: true)
        case .submit: await submitReport()
        case .loadRelationship: await loadRelationship()
        case .accountAction: break  // Retry the chosen action explicitly from its row.
        }
    }
}
