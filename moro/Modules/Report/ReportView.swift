//
//  ReportView.swift
//  moro
//
//  Multi-step report view for reporting statuses or accounts.
//

import SwiftUI

struct ReportView: View {
    let status: Status
    let onDismiss: () -> Void
    
    @StateObject private var viewModel: ReportViewModel
    @Environment(\.moroTheme) private var theme

    private enum Metrics {
        static let cardCornerRadius: CGFloat = 12
    }
    
    init(status: Status, apiClient: MastodonAPI, onDismiss: @escaping () -> Void) {
        self.status = status
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: ReportViewModel(apiClient: apiClient, status: status))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if viewModel.currentStep != .submitting {
                        stepProgressView
                            .padding(.horizontal, theme.spacing.m)
                            .padding(.top, theme.spacing.s)
                            .padding(.bottom, theme.spacing.s)
                    }

                    Group {
                        switch viewModel.currentStep {
                        case .reason:
                            reasonSelectionView
                        case .selectPosts:
                            postSelectionView
                        case .submitting:
                            submittingView
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    leadingToolbarButton
                }
                
                ToolbarItem(placement: .principal) {
                    Text(navigationTitle)
                        .font(theme.typography.subtitle)
                        .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    trailingToolbarButton
                }
            }
            .onChange(of: viewModel.isSubmitted) { _, submitted in
                if submitted {
                    // Provide haptic feedback and dismiss
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onDismiss()
                }
            }
        }
    }
    
    // MARK: - Navigation
    
    private var navigationTitle: String {
        switch viewModel.currentStep {
        case .reason:
            return MoroL10n.Report.title(viewModel.accountUsername)
        case .selectPosts:
            return MoroL10n.Report.selectPostsTitle
        case .submitting:
            return MoroL10n.Report.navTitleSubmitting
        }
    }
    
    @ViewBuilder
    private var leadingToolbarButton: some View {
        switch viewModel.currentStep {
        case .reason:
            Button(MoroL10n.Report.cancel, action: onDismiss)
                .foregroundStyle(theme.colors.textSecondary)
        case .selectPosts:
            MoroNavigationControlButton(kind: .back) { viewModel.goToPreviousStep() }
        case .submitting:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var trailingToolbarButton: some View {
        switch viewModel.currentStep {
        case .reason:
            Button(MoroL10n.Report.nextStep) {
                viewModel.goToNextStep()
            }
            .fontWeight(.semibold)
            .foregroundStyle(viewModel.canProceedToNextStep ? theme.colors.primary500 : theme.colors.textTertiary)
            .disabled(!viewModel.canProceedToNextStep)
        case .selectPosts:
            Button(MoroL10n.Report.submitButton) {
                viewModel.goToNextStep()
            }
            .fontWeight(.bold)
            .foregroundStyle(viewModel.canProceedToNextStep ? theme.colors.error : theme.colors.textTertiary)
            .disabled(!viewModel.canProceedToNextStep)
        case .submitting:
            EmptyView()
        }
    }
    
    // MARK: - Step 1: Reason Selection
    
    private var reasonSelectionView: some View {
        ScrollView {
            VStack(spacing: theme.spacing.m) {
                targetAccountSummaryCard

                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(MoroL10n.Report.selectReason)
                        .font(theme.typography.subtitle)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(MoroL10n.Report.commentHint)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.m)
                .background(theme.colors.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )

                // Reason cards
                ForEach(ReportReason.allCases) { reason in
                    ReportReasonCard(
                        reason: reason,
                        isSelected: viewModel.selectedReason == reason,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedReason = reason
                            }
                        }
                    )
                }
                
                // Custom comment section
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    Text(MoroL10n.Report.commentLabel)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)

                    TextField(MoroL10n.Report.commentPlaceholder, text: $viewModel.customComment, axis: .vertical)
                        .font(theme.typography.body)
                        .lineLimit(3...6)
                        .padding(theme.spacing.m)
                        .background(theme.colors.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(theme.colors.borderSubtle, lineWidth: 1)
                        )
                }
                .padding(.top, theme.spacing.m)
                .padding(theme.spacing.m)
                .background(theme.colors.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )
            }
            .padding(theme.spacing.m)
        }
    }
    
    // MARK: - Step 2: Post Selection
    
    private var postSelectionView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(MoroL10n.Report.selectPosts)
                    .font(theme.typography.subtitle)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(MoroL10n.Report.selectPostsHint)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.m)
            .background(theme.colors.surfaceSubtle)

            HStack(spacing: theme.spacing.s) {
                Text(MoroL10n.Report.reasonLabel)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                Text(viewModel.selectedReason?.title ?? MoroL10n.Report.noReasonSelected)
                    .font(theme.typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
            .background(theme.colors.surfaceBase)
            .overlay(alignment: .bottom) {
                MoroDivider()
            }

            if let stepError = viewModel.stepError {
                InlineFeedbackCard(
                    kind: .error,
                    message: stepError.message,
                    actionTitle: viewModel.stepErrorActionTitle,
                    action: { viewModel.retryStepErrorAction() }
                )
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, theme.spacing.s)
            }

            MoroDivider()
            
            // Status list
            if viewModel.userStatuses.isEmpty && viewModel.isLoadingStatuses {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.userStatuses) { status in
                            ReportStatusRow(
                                status: status,
                                isSelected: viewModel.isStatusSelected(status.id),
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        viewModel.toggleStatusSelection(status.id)
                                    }
                                }
                            )
                            .padding(.horizontal, theme.spacing.m)
                            
                            MoroDivider()
                                .padding(.leading, theme.spacing.m + 36 + theme.spacing.m) // Align with content
                        }
                        
                        // Load more
                        if viewModel.hasMoreStatuses {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(theme.spacing.l)
                                .onAppear {
                                    Task {
                                        await viewModel.loadMoreStatuses()
                                    }
                                }
                        }
                    }
                }
            }
            
            // Selected count footer
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.colors.primary500)
                Text(MoroL10n.Report.selectedCount(viewModel.selectedStatusIDs.count))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer()
            }
            .padding(theme.spacing.s)
            .background(theme.colors.surfaceBase)
            .overlay(alignment: .top) {
                MoroDivider()
            }
        }
    }
    
    // MARK: - Submitting View
    
    private var submittingView: some View {
        VStack(spacing: theme.spacing.l) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(MoroL10n.Report.submitting)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)

            Text(MoroL10n.Report.submittingHint)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepProgressView: some View {
        HStack(spacing: theme.spacing.s) {
            stepTag(index: 1, title: MoroL10n.Report.stepReason, isActive: viewModel.currentStep == .reason, isDone: viewModel.currentStep == .selectPosts)
            stepConnector
            stepTag(index: 2, title: MoroL10n.Report.stepPosts, isActive: viewModel.currentStep == .selectPosts, isDone: false)
            Spacer()

            Text(viewModel.currentStep == .reason ? "1/2" : "2/2")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(theme.spacing.s)
        .background(theme.colors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }

    private var stepConnector: some View {
        Rectangle()
            .fill(theme.colors.borderSubtle)
            .frame(width: 24, height: 1)
    }

    private func stepTag(index: Int, title: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive || isDone ? theme.colors.primary500 : theme.colors.surfaceSubtle)
                    .frame(width: 20, height: 20)
                if isDone {
                    Image(systemName: "checkmark")
                        .moroScaledFont(size: 11, weight: .bold)
                        .foregroundStyle(theme.colors.primaryForeground)
                } else {
                    Text("\(index)")
                        .moroScaledFont(size: 11, weight: .bold)
                        .foregroundStyle(isActive ? theme.colors.primaryForeground : theme.colors.textSecondary)
                }
            }

            Text(title)
                .font(theme.typography.caption)
                .foregroundStyle(isActive || isDone ? theme.colors.textPrimary : theme.colors.textSecondary)
        }
    }

    @ViewBuilder
    private var targetAccountSummaryCard: some View {
        HStack(spacing: theme.spacing.s) {
            MoroAvatar(
                imageURL: status.account.avatarAnimatedURL,
                staticImageURL: status.account.avatarURL,
                initials: status.account.displayNameInitials,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                AccountDisplayNameView(
                    account: status.account,
                    typography: .captionStrong,
                    textColor: theme.colors.textPrimary
                )
                Text("@\(status.account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer()

            Text(MoroL10n.Report.targetLabel)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }
}

#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "problemuser",
        acct: "problemuser@mastodon.social",
        displayName: "Problem User",
        note: "",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 100,
        followingCount: 50,
        statusesCount: 200
    )
    
    let sampleStatus = Status(
        id: "1",
        content: "<p>This is problematic content that should be reported.</p>",
        createdAt: Date(),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 10,
        reblogsCount: 5,
        repliesCount: 2,
        bookmarked: false,
        favourited: false,
        reblogged: false
    )
    
    let state = AppState()
    let interceptor = AuthInterceptor(tokenProvider: state)
    let client = MastodonClient(authInterceptor: interceptor)
    
    ReportView(status: sampleStatus, apiClient: client, onDismiss: {})
        .moroTheme(MoroTheme())
}
