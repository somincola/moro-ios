import SwiftUI

struct ReportView: View {
    let onDismiss: () -> Void
    @Environment(\.moroTheme) private var theme
    @StateObject private var viewModel: ReportViewModel
    @State private var pendingAction: ReportViewModel.AccountAction?
    @FocusState private var isCommentFocused: Bool

    init(status: Status, apiClient: MastodonAPI, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: ReportViewModel(apiClient: apiClient, status: status))
    }

    init(account: Account, apiClient: MastodonAPI, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: ReportViewModel(apiClient: apiClient, account: account))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.currentStep != .result {
                    stepProgress
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if viewModel.currentStep != .result {
                            stepHeading
                        }
                        switch viewModel.currentStep {
                        case .reason: reasonSelection
                        case .rules: ruleSelection
                        case .selectPosts: postSelection
                        case .comment: commentEntry
                        case .result: result
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                }
                .id(viewModel.currentStep)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(theme.colors.surfaceBase)
            .safeAreaInset(edge: .bottom, spacing: 0) { primaryAction }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surfaceBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(MoroL10n.Profile.report)
                        .font(theme.typography.bodyStrong)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.currentStep == .reason {
                        Button(role: .cancel, action: onDismiss) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(MoroL10n.Common.cancel)
                    } else if !viewModel.isSubmitted {
                        Button {
                            isCommentFocused = false
                            viewModel.goToPreviousStep()
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel(MoroL10n.UtilityButton.back)
                        .disabled(viewModel.isBusy)
                    }
                }
            }
            .task(id: viewModel.currentStep) { await viewModel.prepareCurrentStep() }
            .onChange(of: viewModel.isSubmitted) { _, submitted in
                if submitted { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
            .alert(
                actionTitle(pendingAction ?? .block),
                isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
                presenting: pendingAction
            ) { action in
                Button(actionTitle(action), role: .destructive) {
                    Task { await viewModel.performAccountAction(action) }
                }
                Button(MoroL10n.Common.cancel, role: .cancel) {}
            } message: { action in
                Text(actionConfirmation(action))
            }
        }
        .tint(theme.colors.primary500)
        .presentationDetents([.large])
        .presentationBackground(theme.colors.surfaceBase)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.isBusy)
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case .reason: MoroL10n.Report.reasonLabel
        case .rules: MoroL10n.Report.rulesTitle
        case .selectPosts: MoroL10n.Report.selectPosts
        case .comment: MoroL10n.Report.commentTitle
        case .result: ""
        }
    }

    private var stepHint: String? {
        switch viewModel.currentStep {
        case .rules: MoroL10n.Report.rulesHint
        case .selectPosts: MoroL10n.Report.selectPostsHint
        case .comment: MoroL10n.Report.commentHint
        case .reason, .result: nil
        }
    }

    private var stepHeading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stepTitle)
                .moroScaledFont(size: 28, weight: .semibold, relativeTo: .title)
                .foregroundStyle(theme.colors.primary500)
                .accessibilityAddTraits(.isHeader)
            if let stepHint {
                Text(stepHint)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepProgress: some View {
        let steps: [ReportStep] =
            viewModel.selectedReason == .violation
            ? [.reason, .rules, .selectPosts, .comment] : [.reason, .selectPosts, .comment]
        let current = steps.firstIndex(of: viewModel.currentStep) ?? 0
        return HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(theme.colors.primary500.opacity(index <= current ? 1 : 0.14))
                    .frame(height: 2)
            }
        }
        // Content preferences leave the report flow immediately; don't imply remaining report steps.
        .opacity(viewModel.selectedReason == .dislike ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MoroL10n.Profile.report)
        .accessibilityValue("\(current + 1) / \(steps.count)")
        .accessibilityHidden(viewModel.selectedReason == .dislike)
    }

    private var primaryAction: some View {
        let isResult = viewModel.currentStep == .result
        let enabled = isResult ? !viewModel.isBusy : viewModel.canProceedToNextStep
        return VStack(spacing: 14) {
            if viewModel.currentStep == .selectPosts {
                Text(MoroL10n.Report.selectedCount(viewModel.selectedStatusIDs.count))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                isCommentFocused = false
                if isResult {
                    onDismiss()
                } else if viewModel.currentStep == .comment {
                    Task { await viewModel.submitReport() }
                } else {
                    viewModel.goToNextStep()
                }
            } label: {
                ZStack {
                    Text(isResult ? MoroL10n.Common.done : nextButtonTitle)
                        .opacity(viewModel.isSubmitting ? 0 : 1)
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(theme.colors.primaryForeground)
                    }
                }
                .font(theme.typography.subtitle)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(enabled ? theme.colors.primaryForeground : theme.colors.textSecondary)
                .background(theme.colors.primary500.opacity(enabled || viewModel.isSubmitting ? 1 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(
                viewModel.isSubmitting
                    ? MoroL10n.Report.submitting
                    : isResult ? MoroL10n.Common.done : nextButtonTitle)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(theme.colors.surfaceBase)
        .overlay(alignment: .top) { MoroDivider() }
    }

    private var nextButtonTitle: String {
        switch viewModel.currentStep {
        case .selectPosts where viewModel.selectedStatusIDs.isEmpty: MoroL10n.Report.skip
        case .comment: MoroL10n.Report.submitButton
        default: MoroL10n.Report.nextStep
        }
    }

    @ViewBuilder
    private var reasonSelection: some View {
        accountSummary
        VStack(spacing: 0) {
            ForEach(ReportReason.allCases) { reason in
                ReportReasonCard(reason: reason, isSelected: viewModel.selectedReason == reason) {
                    viewModel.selectedReason = reason
                }
            }
        }
    }

    @ViewBuilder
    private var ruleSelection: some View {
        stepError
        LazyVStack(spacing: 0) {
            if viewModel.isLoadingRules {
                loadingRow
            } else if viewModel.rules.isEmpty, viewModel.stepError == nil {
                Text(MoroL10n.Report.noRules)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                Button(MoroL10n.Report.chooseAnotherReason) { viewModel.goToPreviousStep() }
            } else {
                ForEach(viewModel.rules) { rule in
                    let selected = viewModel.selectedRuleIDs.contains(rule.id)
                    Button {
                        viewModel.toggleRuleSelection(rule.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(rule.localizedText)
                                    .moroScaledFont(size: 16, weight: .medium)
                                    .foregroundStyle(theme.colors.primary500)
                                if let hint = rule.localizedHint, !hint.isEmpty {
                                    Text(hint)
                                        .font(theme.typography.body)
                                        .foregroundStyle(theme.colors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            ReportSelectionIndicator(isSelected: selected)
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                        .padding(.vertical, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    MoroDivider()
                }
            }
        }
    }

    @ViewBuilder
    private var postSelection: some View {
        stepError
        accountSummary
        LazyVStack(spacing: 0) {
            ForEach(viewModel.userStatuses) { status in
                ReportStatusRow(status: status, isSelected: viewModel.selectedStatusIDs.contains(status.id)) {
                    viewModel.toggleStatusSelection(status.id)
                }
            }
            if viewModel.isLoadingStatuses {
                loadingRow
            } else if viewModel.userStatuses.isEmpty, viewModel.stepError == nil {
                Text(MoroL10n.Report.noPosts)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
            } else if viewModel.hasMoreStatuses, viewModel.stepError == nil {
                Button(MoroL10n.Report.loadMore) {
                    Task { await viewModel.loadUserStatuses(loadMore: true) }
                }
            }
        }
    }

    @ViewBuilder
    private var commentEntry: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if viewModel.customComment.isEmpty {
                    Text(MoroL10n.Report.commentPlaceholder)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $viewModel.customComment)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 200)
                    .foregroundStyle(theme.colors.primary500)
                    .focused($isCommentFocused)
                    .disabled(viewModel.isSubmitting)
                    .accessibilityLabel(MoroL10n.Report.commentTitle)
            }
            .moroScaledFont(size: 17)
            .padding(12)
            .background(theme.colors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(theme.colors.borderSubtle, lineWidth: 0.5)
            }
            Text("\(viewModel.comment.count) / \(ReportViewModel.commentLimit)")
                .font(theme.typography.caption)
                .monospacedDigit()
                .foregroundStyle(
                    viewModel.comment.count > ReportViewModel.commentLimit
                        ? theme.colors.error : theme.colors.textSecondary)
        }
        stepError
    }

    @ViewBuilder
    private var result: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: viewModel.isSubmitted ? "checkmark" : "slider.horizontal.3")
                .font(.title2.weight(.medium))
                .foregroundStyle(theme.colors.primary500)
                .frame(width: 52, height: 52)
                .background(theme.colors.surfaceSubtle, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    viewModel.isSubmitted
                        ? MoroL10n.Report.successSubmitted : MoroL10n.Report.preferencesTitle
                )
                .moroScaledFont(size: 28, weight: .semibold, relativeTo: .title)
                .foregroundStyle(theme.colors.primary500)
                .accessibilityAddTraits(.isHeader)
                Text(viewModel.isSubmitted ? MoroL10n.Report.resultHint : MoroL10n.Report.dislikeHint)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineSpacing(3)
            }
        }
        stepError
        VStack(spacing: 0) {
            accountSummary
                .padding(.bottom, 20)
            MoroDivider()
            if viewModel.isLoadingRelationship {
                loadingRow
            } else if let relationship = viewModel.relationship {
                if relationship.following || relationship.requested || viewModel.hasUnfollowed {
                    accountActionRow(
                        .unfollow, systemImage: "person.badge.minus", detail: MoroL10n.Report.unfollowHint)
                }
                accountActionRow(.mute, systemImage: "speaker.slash", detail: MoroL10n.Report.muteHint)
                accountActionRow(.block, systemImage: "hand.raised", detail: MoroL10n.Report.blockHint)
            }
        }
    }

    private func accountActionRow(
        _ action: ReportViewModel.AccountAction, systemImage: String, detail: String
    ) -> some View {
        let completed = viewModel.isActionCompleted(action)
        return Button(role: action == .block ? .destructive : nil) {
            requestAccountAction(action)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.colors.primary500)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(actionTitle(action))
                        .moroScaledFont(size: 17, weight: .medium)
                        .foregroundStyle(theme.colors.primary500)
                    Text(detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.activeAccountAction == action {
                    ProgressView()
                } else if completed {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(completed ? 0.55 : 1)
        .disabled(completed || viewModel.isBusy)
        .accessibilityValue(completed ? MoroL10n.Common.done : "")
        .overlay(alignment: .bottom) { MoroDivider() }
    }

    private func requestAccountAction(_ action: ReportViewModel.AccountAction) {
        let settings = AppSettings.shared
        let needsConfirmation: Bool
        switch action {
        case .unfollow: needsConfirmation = settings.askBeforeUnfollowingAUser
        case .mute: needsConfirmation = settings.askBeforeMutingAUser
        case .block: needsConfirmation = settings.askBeforeBlockingAUser
        }
        if needsConfirmation {
            pendingAction = action
        } else {
            Task { await viewModel.performAccountAction(action) }
        }
    }

    private func actionTitle(_ action: ReportViewModel.AccountAction) -> String {
        switch action {
        case .unfollow:
            viewModel.relationship?.requested == true
                ? MoroL10n.Profile.cancelFollowRequest : MoroL10n.MentionUser.unfollowAction
        case .mute: MoroL10n.MentionUser.muteAction
        case .block: MoroL10n.MentionUser.blockAction
        }
    }

    private func actionConfirmation(_ action: ReportViewModel.AccountAction) -> String {
        switch action {
        case .unfollow: MoroL10n.MentionUser.unfollowMessage(viewModel.accountUsername)
        case .mute: MoroL10n.MentionUser.muteMessage(viewModel.accountUsername)
        case .block: MoroL10n.MentionUser.blockMessage(viewModel.accountUsername)
        }
    }

    private var accountSummary: some View {
        let account = viewModel.account
        return HStack(spacing: 12) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL, staticImageURL: account.avatarURL,
                initials: account.displayNameInitials, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                AccountDisplayNameView(
                    account: account, typography: .bodyStrong,
                    textColor: theme.colors.primary500, lineLimit: 1)
                Text("@\(account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var loadingRow: some View {
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: 32)
    }

    @ViewBuilder
    private var stepError: some View {
        if let error = viewModel.stepError {
            VStack(alignment: .leading, spacing: 12) {
                Label(error.message, systemImage: "exclamationmark.circle")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                if error.context != .accountAction {
                    Button(MoroL10n.Report.retry) {
                        Task { await viewModel.retryStepErrorAction() }
                    }
                    .frame(minHeight: 44)
                    .disabled(viewModel.isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.colors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
