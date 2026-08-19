//
//  AccountReportView.swift
//  moro
//
//  Account-level report view from profile more menu.
//

import SwiftUI

struct AccountReportView: View {
    let account: Account
    let onDismiss: () -> Void

    @StateObject private var viewModel: AccountReportViewModel
    @Environment(\.moroTheme) private var theme

    init(account: Account, apiClient: MastodonAPI, onDismiss: @escaping () -> Void) {
        self.account = account
        self.onDismiss = onDismiss
        _viewModel = StateObject(
            wrappedValue: AccountReportViewModel(apiClient: apiClient, account: account)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing.m) {
                    targetAccountSummaryCard

                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text(MoroL10n.AccountReport.title)
                        .font(theme.typography.subtitle)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text(MoroL10n.AccountReport.desc)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(theme.spacing.m)
                    .background(theme.colors.surfaceBase)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.colors.borderSubtle, lineWidth: 1)
                    )

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

                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        Text(MoroL10n.AccountReport.commentLabel)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)

                        TextField(MoroL10n.AccountReport.commentPlaceholder, text: $viewModel.customComment, axis: .vertical)
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
                    .padding(.top, theme.spacing.s)

                    if viewModel.isSubmitting {
                        InlineFeedbackCard(
                            kind: .info,
                            message: MoroL10n.AccountReport.submitting
                        )
                    }

                    if let errorMessage = viewModel.errorMessage {
                        InlineFeedbackCard(
                            kind: .error,
                            message: errorMessage,
                            actionTitle: MoroL10n.AccountReport.retrySubmit,
                            action: {
                                Task {
                                    await viewModel.submit()
                                }
                            }
                        )
                    }
                }
                .padding(theme.spacing.m)
            }
            .background(theme.colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    MoroNavigationControlButton(kind: .close, action: onDismiss)
                }

                ToolbarItem(placement: .principal) {
                    Text(MoroL10n.AccountReport.navTitle(viewModel.accountUsername))
                        .font(theme.typography.subtitle)
                        .fontWeight(.semibold)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSubmitting ? MoroL10n.AccountReport.submitButtonLoading : MoroL10n.AccountReport.submitButtonActive) {
                        Task {
                            await viewModel.submit()
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(viewModel.canSubmit ? theme.colors.error : theme.colors.textTertiary)
                    .disabled(!viewModel.canSubmit)
                }
            }
        }
        .onChange(of: viewModel.isSubmitted) { _, submitted in
            if submitted {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDismiss()
            }
        }
    }

    @ViewBuilder
    private var targetAccountSummaryCard: some View {
        HStack(spacing: theme.spacing.s) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: theme.colors.textPrimary
                )
                Text("@\(account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer()

            Text(MoroL10n.AccountReport.badge)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

    let state = AppState()
    let interceptor = AuthInterceptor(tokenProvider: state)
    let client = MastodonClient(authInterceptor: interceptor)

    AccountReportView(account: sampleAccount, apiClient: client, onDismiss: {})
        .moroTheme(MoroTheme())
}
