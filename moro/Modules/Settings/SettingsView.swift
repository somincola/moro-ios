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

    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
    }

    private var hasAccountContext: Bool {
        appState.currentAccount != nil || apiClient != nil
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
        List {
            menuRows
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: MoroLayoutMetrics.contentHorizontalInset,
                    bottom: 0,
                    trailing: MoroLayoutMetrics.contentHorizontalInset
                ))
                .listRowSeparator(.visible, edges: .bottom)
        }
        .moroSettingsListChrome()
        .listSectionSpacing(28)
        .environment(\.defaultMinListRowHeight, Metrics.minimumRowHeight)
        .listRowSeparatorTint(theme.colors.borderSubtle)
        .moroSettingsSwitchStyle()
        .navigationTitle(MoroL10n.Settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await storage.refresh() }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menuRows: some View {
        if hasAccountContext {
            Section {
                accountManagementRow
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

            if hasAccountContext {
                NavigationLink {
                    NotificationSettingsView(apiClient: apiClient, mode: .push)
                } label: {
                    settingsRow(MoroL10n.NotificationSettings.sectionPush, icon: "bell.badge")
                }
                .accessibilityIdentifier("settings.push")
            }

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
        } header: {
            MoroSettingsSectionHeader(title: MoroL10n.Settings.appSection)
        } footer: {
            Text(MoroL10n.Settings.localScope)
        }

        if hasAccountContext {
            Section {
                if let apiClient {
                    NavigationLink {
                        EditProfileView(apiClient: apiClient, currentAccount: currentAccount)
                    } label: {
                        settingsRow(MoroL10n.Settings.profile, icon: "person.crop.circle")
                    }
                    .accessibilityIdentifier("settings.profile")
                }

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
                }

                NavigationLink {
                    NotificationSettingsView(apiClient: apiClient, mode: .intake)
                } label: {
                    settingsRow(MoroL10n.Settings.notificationRules, icon: "tray")
                }
                .accessibilityIdentifier("settings.notificationRules")

                if let apiClient {
                    NavigationLink {
                        InstanceDetailsView(apiClient: apiClient)
                    } label: {
                        settingsRow(MoroL10n.Settings.thisServer, icon: "building.2")
                    }
                    .accessibilityIdentifier("settings.server")
                }

                if let activeSession {
                    NavigationLink {
                        ServerAccountActionsView(session: activeSession)
                    } label: {
                        settingsRow(MoroL10n.AccountMgmt.deleteAccount, icon: "trash", color: .red)
                    }
                    .accessibilityIdentifier("settings.accountActions")
                    .listRowSeparator(.hidden, edges: .bottom)
                }
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Settings.currentAccountSection)
            }
        }

        Section {
            NavigationLink {
                FeedbackView(apiClient: apiClient)
            } label: { settingsRow(MoroL10n.AppSupport.feedback, icon: "bubble.left") }
            .accessibilityIdentifier("settings.feedback")

            aboutRow
        } header: {
            MoroSettingsSectionHeader(title: MoroL10n.Settings.supportAboutSection)
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
                settingsRow(MoroL10n.Settings.loginManagement, icon: "person.2")
            }
            .accessibilityIdentifier("settings.accounts")
            .listRowSeparator(.hidden, edges: .bottom)
        }
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
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(minHeight: Metrics.minimumRowHeight)
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
