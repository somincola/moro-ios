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
        static let iconColumnWidth: CGFloat = 24
        static let iconSymbolSize: CGFloat = 18
        static let minimumRowHeight: CGFloat = 52
        static let rowVerticalPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 12
    }

    @State private var showLogoutConfirmation = false

    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
    }

    private var hasAccountContext: Bool {
        appState.currentAccount != nil || apiClient != nil
    }

    private var currentAccountDomain: String? {
        let resolvedAccount =
            appState.currentAccount
            ?? ctx.accountSessions.first(where: { $0.id == ctx.activeSessionID })?.account
            ?? ctx.accountSessions.first?.account

        guard let urlString = resolvedAccount?.url,
            let url = URL(string: urlString)
        else {
            return nil
        }
        return url.host
    }

    var body: some View {
        List {
            menuRows
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.visible, edges: .bottom)
        }
        .moroSettingsListChrome()
        .listSectionSpacing(20)
        .environment(\.defaultMinListRowHeight, Metrics.minimumRowHeight)
        .listRowSeparatorTint(theme.colors.borderSubtle)
        .moroSettingsSwitchStyle()
        .navigationTitle(MoroL10n.Settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await storage.refresh() }
        .alert(MoroL10n.Settings.logoutAlertTitle, isPresented: $showLogoutConfirmation) {
            Button(MoroL10n.Common.cancel, role: .cancel) {}
            Button(MoroL10n.Settings.logoutAction, role: .destructive) {
                ctx.onLogout()
            }
        } message: {
            Text(MoroL10n.Settings.logoutAlertMessage)
        }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menuRows: some View {
        if hasAccountContext {
            Section {
                accountManagementRow

                if let apiClient {
                    NavigationLink {
                        InstanceDetailsView(apiClient: apiClient)
                    } label: {
                        settingsRow(MoroL10n.Settings.thisServer, icon: "building.2")
                    }
                    .accessibilityIdentifier("settings.server")
                    .listRowSeparator(.hidden, edges: .bottom)
                }
            } header: {
                sectionHeader(MoroL10n.Settings.accountServerSection)
            }
        }

        Section {
            preferencesRow

            if hasAccountContext {
                NavigationLink {
                    NotificationSettingsView(apiClient: apiClient)
                } label: {
                    settingsRow(MoroL10n.Settings.notificationsSubscriptions, icon: "bell.badge")
                }

                NavigationLink {
                    PrivacySafetySettingsView(apiClient: apiClient)
                } label: {
                    settingsRow(MoroL10n.Settings.privacySafety, icon: "hand.raised")
                }
            }

            emojiRow
            NavigationLink {
                StorageSettingsView()
            } label: {
                settingsRow(
                    MoroL10n.AppSupport.storage,
                    icon: "internaldrive",
                    value: storage.usage.map { StorageManagementStore.formatted($0.total) }
                )
            }
            .accessibilityIdentifier("settings.storage")
            .listRowSeparator(.hidden, edges: .bottom)
        } header: {
            sectionHeader(MoroL10n.Settings.appSection)
        }

        Section {
            NavigationLink {
                FeedbackView(apiClient: apiClient)
            } label: { settingsRow(MoroL10n.AppSupport.feedback, icon: "bubble.left") }
            .accessibilityIdentifier("settings.feedback")

            aboutRow
        } header: {
            sectionHeader(MoroL10n.Settings.supportAboutSection)
        }

        if hasAccountContext {
            Section {
                logoutRow
            }
        }
    }

    @ViewBuilder
    private var accountManagementRow: some View {
        if hasAccountContext {
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
                settingsRow(MoroL10n.Settings.switchAccount, icon: "person.2")
            }
            .accessibilityIdentifier("settings.accounts")
            .listRowSeparator(apiClient == nil ? .hidden : .visible, edges: .bottom)
        }
    }

    @ViewBuilder
    private var preferencesRow: some View {
        NavigationLink {
            GeneralSettingsView()
        } label: {
            settingsRow(MoroL10n.Settings.readingBrowsingSection, icon: "slider.horizontal.3")
        }
        .accessibilityIdentifier("settings.preferences")
    }

    private var emojiRow: some View {
        NavigationLink {
            if let domain = currentAccountDomain {
                EmojiManagementView(domain: domain, apiClient: apiClient)
            } else {
                EmojiManagementUnavailableView()
            }
        } label: {
            settingsRow(MoroL10n.Settings.emojiManagement, icon: "face.smiling")
        }
        .accessibilityIdentifier("settings.emoji")
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

    private var logoutRow: some View {
        Button(role: .destructive) {
            showLogoutConfirmation = true
        } label: {
            settingsRow(
                MoroL10n.Settings.logout,
                icon: "rectangle.portrait.and.arrow.right",
                color: .red
            )
            .fontWeight(.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden, edges: .bottom)
    }

    // MARK: - Reusable Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(theme.typography.caption)
            .fontWeight(.medium)
            .foregroundStyle(theme.colors.textSecondary)
            .textCase(nil)
    }

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
                    .moroScaledFont(size: 17)
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
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(minHeight: Metrics.minimumRowHeight)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + iconColumnWidth * theme.fontScale + Metrics.rowSpacing
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
            .frame(width: iconColumnWidth * theme.fontScale, alignment: .center)
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
