//
//  AccountGovernanceView.swift
//  moro
//
//  Centralized muted/blocked account management pages.
//

import SwiftUI

struct AccountGovernanceView: View {
    @Environment(\.moroTheme) private var theme
    @StateObject private var viewModel: AccountGovernanceViewModel

    private let apiClient: MastodonAPI

    init(kind: AccountGovernanceKind, apiClient: MastodonAPI) {
        self.apiClient = apiClient
        _viewModel = StateObject(
            wrappedValue: AccountGovernanceViewModel(kind: kind, apiClient: apiClient)
        )
    }

    var body: some View {
        MoroSettingsList {
            if let transientErrorMessage = viewModel.transientErrorMessage {
                Section {
                    MoroInlineNoticeBanner(
                        message: transientErrorMessage,
                        tone: .error,
                        actionTitle: MoroL10n.GovernanceView.retry,
                        action: { Task { await viewModel.refresh() } }
                    )
                }
            }

            accountSection
        }
        .moroSettingsListChrome()
        .navigationTitle(viewModel.kind.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if viewModel.accounts.isEmpty && isLoadingState {
            Section {
                MoroLoadingStateView(mascotSize: 38)
                    .frame(minHeight: 160)
            }
        } else if viewModel.accounts.isEmpty, case .error(let error) = viewModel.loadingState {
            Section {
                ErrorStateView(
                    spec: ErrorStateSpec(
                        title: MoroL10n.GovernanceView.loadFailed,
                        message: MoroErrorCopy.message(for: error),
                        actionTitle: MoroL10n.GovernanceView.retry,
                        action: { Task { await viewModel.refresh() } }
                    )
                )
                .frame(minHeight: 240)
            }
        } else if viewModel.accounts.isEmpty {
            Section {
                EmptyStateView(
                    spec: EmptyStateSpec(
                        icon: "person.slash",
                        title: viewModel.kind.emptyTitle,
                        message: viewModel.kind.emptyMessage,
                        mascot: .calm
                    )
                )
                .frame(minHeight: 240)
            }
        } else {
            Section {
                ForEach(viewModel.accounts) { account in
                    NavigationLink {
                        ProfileView(
                            account: account,
                            accountID: account.id,
                            onLogout: {},
                            apiClient: apiClient
                        )
                    } label: {
                        AccountGovernanceRow(
                            account: account,
                            isMutating: viewModel.isMutating(accountID: account.id)
                        )
                    }
                    .disabled(viewModel.isMutating(accountID: account.id))
                    .accessibilityIdentifier("governance.account.\(account.id)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task {
                                await viewModel.release(account)
                            }
                        } label: {
                            Label {
                                Text(viewModel.kind.releaseActionTitle)
                            } icon: {
                                MoroMenuGlyph(systemImage: "person.crop.circle.badge.minus", tintColor: .white)
                            }
                            .labelStyle(.titleAndIcon)
                        }
                        .tint(theme.colors.error)
                        .disabled(viewModel.isMutating(accountID: account.id))
                        .accessibilityIdentifier("governance.release.\(account.id)")
                    }
                }
            } header: {
                MoroSettingsSectionHeader(title: viewModel.kind.sectionTitle)
            } footer: {
                Text(viewModel.kind.footerText)
            }
        }
    }

    private var isLoadingState: Bool {
        if case .idle = viewModel.loadingState {
            return true
        }
        if case .loading = viewModel.loadingState {
            return true
        }
        return false
    }
}

private struct AccountGovernanceRow: View {
    @Environment(\.moroTheme) private var theme

    let account: Account
    let isMutating: Bool

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials, seed: account.placeholderSeed,
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
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

            Spacer(minLength: theme.spacing.s)

            if isMutating {
                ProgressView()
                    .scaleEffect(0.85)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AccountGovernanceView(
            kind: .muted,
            apiClient: MastodonClient(authInterceptor: AuthInterceptor(tokenProvider: AppState()))
        )
        .moroTheme(MoroTheme())
    }
}
