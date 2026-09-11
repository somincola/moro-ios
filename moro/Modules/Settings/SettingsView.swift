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
    @EnvironmentObject private var appState: AppState

    let apiClient: MastodonAPI?
    @ObservedObject private var storage = StorageManagementStore.shared

    private enum Metrics {
        static let iconColumnWidth: CGFloat = 26
        static let iconSymbolSize: CGFloat = 18
        static let minimumRowHeight: CGFloat = 44
        static let rowVerticalPadding: CGFloat = 4
        static let rowSpacing: CGFloat = 14
    }

    @State private var showLogoutConfirmation = false

    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
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
        }
        .moroSettingsListChrome()
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
        Section {
            accountManagementRow

            preferencesRow

            if appState.currentAccount != nil || apiClient != nil {
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
                HStack {
                    settingsRow(MoroL10n.AppSupport.storage, icon: "internaldrive")
                    if let usage = storage.usage {
                        Text(StorageManagementStore.formatted(usage.total))
                            .font(.subheadline).foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }
            .accessibilityIdentifier("settings.storage")
        } header: {
            Text(MoroL10n.Settings.appSection)
        }

        Section {
            if let apiClient {
                NavigationLink {
                    InstanceDetailsView(apiClient: apiClient)
                } label: {
                    settingsRow(MoroL10n.Settings.thisServer, icon: "building.2")
                }
            }

            NavigationLink {
                FeedbackView(apiClient: apiClient)
            } label: { settingsRow(MoroL10n.AppSupport.feedback, icon: "bubble.left") }
            .accessibilityIdentifier("settings.feedback")

            aboutRow
        } header: {
            Text(MoroL10n.Settings.aboutSection)
        }

        if appState.currentAccount != nil || apiClient != nil {
            Section {
                logoutRow
            }
        }
    }

    @ViewBuilder
    private var accountManagementRow: some View {
        if appState.currentAccount != nil || apiClient != nil {
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
        }
    }

    @ViewBuilder
    private var preferencesRow: some View {
        NavigationLink {
            GeneralSettingsView()
        } label: {
            settingsRow(MoroL10n.Settings.readingBrowsingSection, icon: "slider.horizontal.3")
        }
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
    }

    private var aboutRow: some View {
        NavigationLink {
            AboutView()
        } label: {
            settingsRow(MoroL10n.Settings.aboutMoro, icon: "info.circle")
        }
        .accessibilityIdentifier("settings.about")
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
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func settingsRow(
        _ title: String,
        icon: String,
        color: Color? = nil
    ) -> some View {
        let foregroundColor = color ?? theme.colors.textPrimary

        HStack(spacing: Metrics.rowSpacing) {
            settingsIcon(icon, color: foregroundColor)

            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(foregroundColor)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.rowVerticalPadding)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading]
        }
    }

    @ViewBuilder
    private func settingsIcon(_ systemName: String, color: Color? = nil) -> some View {
        Image(systemName: systemName)
            .moroScaledFont(size: Metrics.iconSymbolSize, weight: .regular)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color ?? theme.colors.textPrimary)
            .frame(width: Metrics.iconColumnWidth, alignment: .center)
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
