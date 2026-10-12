//
//  AccountManagementView.swift
//  moro
//
//  Multi-account list and account management entry point.
//

import SwiftUI

struct AccountManagementView: View {
    private enum Metrics {
        // The inset-grouped list already supplies the page margin. Avoid
        // stacking another horizontal inset around the account cards.
        static let accountRowOuterInset: CGFloat = 0
        static let accountRowInnerInset: CGFloat = 12
        static let accountContentInset = accountRowOuterInset + accountRowInnerInset
    }

    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsContext) private var settingsContext
    @EnvironmentObject private var appState: AppState

    let accountSessions: [StoredAccountSession]
    let activeSessionID: String?
    let apiClient: MastodonAPI?
    let onSwitchAccount: (String) -> Void
    let onAddAccount: () -> Void
    let onRemoveAccount: (String) -> Void

    @State private var pendingRemovalSession: StoredAccountSession?
    @State private var showLogoutConfirmation = false
    @State private var editProfileRoute: EditProfileRoute?

    // ponytail: item-based destination instead of isPresented — the bool overload's pop
    // didn't sync with dismiss()/edge-swipe, leaving Edit Profile with no way back.
    private enum EditProfileRoute: Hashable { case edit }

    private var orderedSessions: [StoredAccountSession] {
        guard let activeSessionID else { return accountSessions }
        let current = accountSessions.filter { $0.id == activeSessionID }
        let others = accountSessions.filter { $0.id != activeSessionID }
        return current + others
    }

    var body: some View {
        List {
            ForEach(orderedSessions) { session in
                accountRow(session)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(
                        EdgeInsets(
                            top: 6,
                            leading: Metrics.accountRowOuterInset,
                            bottom: 6,
                            trailing: Metrics.accountRowOuterInset
                        )
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingRemovalSession = session
                        } label: {
                            Label(MoroL10n.AccountMgmt.remove, systemImage: "trash")
                        }
                        .tint(.red)
                    }
            }

            Button {
                dismiss()
                onAddAccount()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(theme.colors.borderSubtle, lineWidth: 1.5)
                        Image(systemName: "plus")
                            .moroScaledFont(size: 18, weight: .semibold)
                            .foregroundStyle(theme.colors.primary500)
                    }
                    .frame(width: 44, height: 44)

                    Text(MoroL10n.AccountMgmt.addAccount)
                        .font(theme.typography.bodyStrong)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, Metrics.accountRowInnerInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.colors.surfaceSubtle)
                )
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: 6,
                    leading: Metrics.accountRowOuterInset,
                    bottom: 6,
                    trailing: Metrics.accountRowOuterInset
                )
            )

            if !orderedSessions.isEmpty {
                Text(MoroL10n.AccountMgmt.swipeToRemoveHint)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: Metrics.accountContentInset,
                            bottom: 8,
                            trailing: Metrics.accountContentInset
                        )
                    )
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    Label(MoroL10n.Settings.logout, systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.logout")
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Settings.loginManagement)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            MoroL10n.AccountMgmt.removeTitle,
            isPresented: Binding(
                get: { pendingRemovalSession != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRemovalSession = nil
                    }
                }
            ),
            presenting: pendingRemovalSession
        ) { session in
            Button(MoroL10n.AccountMgmt.cancel, role: .cancel) {
                pendingRemovalSession = nil
            }
            Button(MoroL10n.AccountMgmt.remove, role: .destructive) {
                pendingRemovalSession = nil
                onRemoveAccount(session.id)
            }
        } message: { session in
            if session.id == activeSessionID {
                Text(MoroL10n.AccountMgmt.removeHint1)
            } else {
                Text(MoroL10n.AccountMgmt.removeHint2)
            }
        }
        .alert(MoroL10n.Settings.logoutAlertTitle, isPresented: $showLogoutConfirmation) {
            Button(MoroL10n.Common.cancel, role: .cancel) {}
            Button(MoroL10n.Settings.logoutAction, role: .destructive) {
                settingsContext.onLogout()
            }
        } message: {
            Text(MoroL10n.Settings.logoutAlertMessage)
        }
        .navigationDestination(item: $editProfileRoute) { _ in
            if let apiClient {
                EditProfileView(
                    apiClient: apiClient,
                    currentAccount: appState.currentAccount
                )
            } else {
                EmptyView()
            }
        }
    }

    /// One account row: tap the current account to edit it, tap another account to switch.
    /// Removal is deliberately only exposed through the row's trailing swipe action.
    @ViewBuilder
    private func accountRow(_ session: StoredAccountSession) -> some View {
        let isCurrent = session.id == activeSessionID
        if isCurrent {
            // Tapping the current account opens Edit Profile (no inline pencil).
            if apiClient != nil {
                Button {
                    editProfileRoute = .edit
                } label: {
                    sessionRow(session, isCurrent: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(MoroL10n.AccountMgmt.editProfile)
            } else {
                sessionRow(session, isCurrent: true)
            }
        } else {
            Button {
                dismiss()
                onSwitchAccount(session.id)
            } label: {
                sessionRow(session, isCurrent: false)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func sessionRow(
        _ session: StoredAccountSession,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: 12) {
            MoroAvatar(
                imageURL: session.account.avatarAnimatedURL,
                staticImageURL: session.account.avatarURL,
                initials: session.account.displayNameInitials,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                AccountDisplayNameView(
                    account: session.account,
                    typography: .body,
                    textColor: theme.colors.textPrimary
                )
                Text("@\(session.account.acct) · \(session.instanceHost)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if isCurrent {
                // Filled accent badge with a punched-out check. Edit Profile is
                // reached by tapping the current-account row (see accountRow).
                Image(systemName: "checkmark.circle.fill")
                    .moroScaledFont(size: 22, weight: .regular)
                    .foregroundStyle(theme.colors.primary500)
                    .accessibilityLabel(MoroL10n.AccountMgmt.currentAccount)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, Metrics.accountRowInnerInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        )
    }
}

struct ServerAccountActionsView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var deletionOpenFailed = false

    let session: StoredAccountSession

    var body: some View {
        List {
            Section {
                serverAccountDeletionLink(for: session)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: theme.spacing.contentHorizontalInset,
                        bottom: 0,
                        trailing: theme.spacing.contentHorizontalInset
                    ))
            } footer: {
                Text(MoroL10n.AccountMgmt.deleteFooter(session.instanceHost))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.AccountMgmt.deleteAccount)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            MoroL10n.AccountMgmt.deleteOpenFailedTitle,
            isPresented: $deletionOpenFailed
        ) {
            Button(MoroL10n.Common.ok, role: .cancel) {}
        } message: {
            Text(MoroL10n.AccountMgmt.deleteOpenFailedMessage)
        }
    }

    private func serverAccountDeletionLink(
        for session: StoredAccountSession
    ) -> some View {
        Button(role: .destructive) {
            openAccountDeletion(for: session)
        } label: {
            HStack(spacing: 12) {
                Text(MoroL10n.AccountMgmt.deleteAccount)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(theme.typography.caption)
                    .accessibilityHidden(true)
            }
            .font(.body)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MoroL10n.AccountMgmt.deleteAccount)
        .accessibilityHint(MoroL10n.AccountMgmt.deleteFooter(session.instanceHost))
        .accessibilityIdentifier("accountManagement.serverAccountSettings")
    }

    private func openAccountDeletion(for session: StoredAccountSession) {
        guard let instanceURL = session.instanceURL,
              let deletionURL = MastodonAccountDeletionURL.make(from: instanceURL) else {
            deletionOpenFailed = true
            return
        }

        openURL(deletionURL) { accepted in
            if !accepted {
                deletionOpenFailed = true
            }
        }
    }
}
