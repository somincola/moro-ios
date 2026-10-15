//
//  SettingsView.swift
//  moro
//
//  Settings page with account options and app preferences.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.settingsContext) private var ctx
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appState: AppState

    let apiClient: MastodonAPI?
    @ObservedObject private var storage = StorageManagementStore.shared
    @ScaledMetric(relativeTo: .body) private var iconColumnWidth = Metrics.iconColumnWidth

    private enum Metrics {
        static let iconColumnWidth = MoroSettingsMetrics.iconColumnWidth
        static let iconSymbolSize = MoroSettingsMetrics.iconPointSize
        static let rowVerticalPadding: CGFloat = 4
        static let rowSpacing = MoroSettingsMetrics.iconTitleSpacing
        static let accountAvatarSize: CGFloat = 52
    }

    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
    }

    private var currentAccount: Account? {
        appState.currentAccount
            ?? ctx.accountSessions.first(where: { $0.id == ctx.activeSessionID })?.account
            ?? ctx.accountSessions.first?.account
    }

    private var activeSession: StoredAccountSession? {
        ctx.accountSessions.first { $0.id == ctx.activeSessionID }
    }

    private var currentAccountDomain: String? {
        guard let urlString = currentAccount?.url,
            let url = URL(string: urlString)
        else {
            return nil
        }
        return url.host
    }

    var body: some View {
        MoroSettingsList {
            menuRows
        }
        .moroSettingsListChrome()
        .moroSettingsSwitchStyle()
        .navigationTitle(MoroL10n.Settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await storage.refresh() }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menuRows: some View {
        if let currentAccount {
            Section {
                accountCardRow(currentAccount)
            }
        }

        Section {
            NavigationLink {
                DisplaySettingsView()
            } label: {
                settingsRow(MoroL10n.Settings.appearanceDisplay, icon: "circle.lefthalf.filled")
            }
            .accessibilityIdentifier("settings.display")

            NavigationLink {
                ReadingSettingsView(apiClient: apiClient)
            } label: {
                settingsRow(MoroL10n.Settings.readingMedia, icon: "text.book.closed")
            }
            .accessibilityIdentifier("settings.reading")

            NavigationLink {
                PostingSettingsView(domain: currentAccountDomain, apiClient: apiClient)
            } label: {
                settingsRow(MoroL10n.Settings.postingInteractions, icon: "square.and.pencil")
            }
            .accessibilityIdentifier("settings.posting")

            NavigationLink {
                NotificationSettingsView(apiClient: apiClient)
            } label: {
                settingsRow(MoroL10n.NotificationSettings.title, icon: "bell.badge")
            }
            .accessibilityIdentifier("settings.notifications")
            .listRowSeparator(.hidden, edges: .bottom)
        }

        Section {
            NavigationLink {
                PrivacySafetySettingsView(apiClient: apiClient)
            } label: {
                settingsRow(MoroL10n.Settings.privacyVisibility, icon: "hand.raised")
            }
            .accessibilityIdentifier("settings.privacy")

            if let apiClient {
                NavigationLink {
                    ContentSafetySettingsView(apiClient: apiClient)
                } label: {
                    settingsRow(MoroL10n.Settings.contentSafety, icon: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("settings.contentSafety")
                .listRowSeparator(.hidden, edges: .bottom)
            }
        }

        Section {
            NavigationLink {
                StorageSettingsView()
            } label: {
                settingsRow(
                    MoroL10n.Settings.storageData,
                    icon: "internaldrive",
                    value: storage.usage.map { StorageManagementStore.formatted($0.total) }
                )
            }
            .accessibilityIdentifier("settings.storage")
            .listRowSeparator(.hidden, edges: .bottom)
        }

        Section {
            NavigationLink {
                FeedbackView(apiClient: apiClient)
            } label: { settingsRow(MoroL10n.AppSupport.feedback, icon: "bubble.left") }
            .accessibilityIdentifier("settings.feedback")

            aboutRow
        }
    }

    /// Identity card at the top of Settings; the single entry to sign-ins, profile,
    /// server details, sign-out and account deletion.
    private func accountCardRow(_ account: Account) -> some View {
        NavigationLink {
            AccountManagementView(
                accountSessions: ctx.accountSessions,
                activeSessionID: ctx.activeSessionID,
                apiClient: apiClient,
                onSwitchAccount: ctx.onSwitchAccount,
                onAddAccount: ctx.onAddAccount,
                onRemoveAccount: ctx.onRemoveAccount
            )
        } label: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                MoroAvatar(
                    imageURL: account.avatarAnimatedURL,
                    staticImageURL: account.avatarURL,
                    initials: account.displayNameInitials, seed: account.placeholderSeed,
                    size: Metrics.accountAvatarSize
                )
                VStack(alignment: .leading, spacing: 3) {
                    AccountDisplayNameView(
                        account: account,
                        typography: .subtitle,
                        textColor: theme.colors.textPrimary
                    )
                    Text(accountHandle(account))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("settings.accounts")
        .listRowSeparator(.hidden)
    }

    private func accountHandle(_ account: Account) -> String {
        let host = activeSession?.instanceHost ?? currentAccountDomain
        guard let host, !account.acct.contains("@") else { return "@\(account.acct)" }
        return "@\(account.acct)@\(host)"
    }

    private var aboutRow: some View {
        NavigationLink {
            AboutView()
        } label: {
            settingsRow(MoroL10n.Settings.aboutMoro, icon: "info.circle")
        }
        .accessibilityIdentifier("settings.about")
        .listRowSeparator(.hidden, edges: .bottom)
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func settingsRow(
        _ title: String,
        icon: String,
        value: String? = nil,
        color: Color? = nil
    ) -> some View {
        let foregroundColor = color ?? theme.colors.textPrimary

        HStack(spacing: Metrics.rowSpacing) {
            settingsIcon(icon, color: color ?? theme.colors.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(foregroundColor)
                    .fixedSize(horizontal: false, vertical: true)

                if dynamicTypeSize.isAccessibilitySize, let value {
                    valueLabel(value)
                }
            }

            Spacer(minLength: 8)

            if !dynamicTypeSize.isAccessibilitySize, let value {
                valueLabel(value)
            }
        }
        // Height comes from the shared list minimum so every settings row matches.
        .padding(.vertical, Metrics.rowVerticalPadding)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + iconColumnWidth + Metrics.rowSpacing
        }
    }

    private func valueLabel(_ value: String) -> some View {
        Text(value)
            .font(theme.typography.body)
            .monospacedDigit()
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize()
    }

    @ViewBuilder
    private func settingsIcon(_ systemName: String, color: Color? = nil) -> some View {
        Image(systemName: systemName)
            .moroScaledFont(size: Metrics.iconSymbolSize, weight: .regular)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color ?? theme.colors.textPrimary)
            .frame(width: iconColumnWidth, alignment: .center)
    }
}

#Preview {
    let state = AppState()
    state.currentAccount = Account(
        id: "1",
        username: "testuser",
        acct: "testuser@mastodon.social",
        displayName: "Test User",
        note: "This is a test bio",
        avatar: "https://example.com/avatar.png",
        avatarStatic: "https://example.com/avatar.png",
        header: "https://example.com/header.png",
        headerStatic: "https://example.com/header.png",
        followersCount: 1234,
        followingCount: 567,
        statusesCount: 890,
        createdAt: Date(),
        locked: false,
        bot: false,
        fields: []
    )

    return NavigationStack {
        SettingsView()
            .environmentObject(state)
            .moroTheme(MoroTheme())
    }
}
