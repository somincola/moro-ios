//
//  NotificationSettingsView.swift
//  moro
//
//  Server notification intake policy and this device's push preferences.
//

import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    enum Mode { case push, intake }

    @Environment(\.activeAccountKey) private var activeAccountKey

    let apiClient: MastodonAPI?
    let mode: Mode

    init(apiClient: MastodonAPI? = nil, mode: Mode = .intake) {
        self.apiClient = apiClient
        self.mode = mode
    }

    var body: some View {
        NotificationSettingsContentView(
            apiClient: apiClient,
            accountKey: activeAccountKey,
            mode: mode
        )
        .id(activeAccountKey)
    }
}

private struct NotificationSettingsContentView: View {
    @Environment(\.moroTheme) private var theme
    @StateObject private var settings = AppSettings.shared
    @StateObject private var pushRegistration = PushRegistrationCenter.shared
    @ObservedObject private var pushSync = PushSubscriptionCoordinator.shared
    @StateObject private var policyController: NotificationPolicyController

    let apiClient: MastodonAPI?
    let accountKey: String
    let mode: NotificationSettingsView.Mode

    init(apiClient: MastodonAPI?, accountKey: String, mode: NotificationSettingsView.Mode) {
        self.apiClient = mode == .push ? (apiClient as? MastodonClient)?.sessionSnapshot() ?? apiClient : apiClient
        self.accountKey = accountKey
        self.mode = mode
        _policyController = StateObject(
            wrappedValue: NotificationPolicyController(accountKey: accountKey)
        )
    }

    var body: some View {
        List {
            if mode == .intake {
                notificationIntakeSection
            } else {
                pushPreferencesSection
            }
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome(separators: .visible)
        .textCase(nil)
        .navigationTitle(mode == .push
            ? MoroL10n.NotificationSettings.sectionPush
            : MoroL10n.Settings.notificationRules)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(mode == .push ? "notificationSettings.pushPage" : "notificationSettings.intakePage")
        .task {
            guard let apiClient else {
                policyController.markUnsupported()
                return
            }
            if mode == .intake {
                await policyController.refresh(using: apiClient)
            } else if PushRegistrationCenter.isPushCapabilityEnabled {
                await pushRegistration.refreshAuthorizationStatus()
                pushSync.resumeSettings(apiClient: apiClient, sessionKey: accountKey)
            }
        }
        .onChange(of: pushRegistration.deviceTokenHex) { _, _ in
            guard mode == .push, let apiClient else { return }
            pushSync.resumeSettings(apiClient: apiClient, sessionKey: accountKey)
        }
    }

    @ViewBuilder
    private var notificationIntakeSection: some View {
        Section {
            switch policyController.loadState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .accessibilityLabel(MoroL10n.NotificationSettings.title)

            case .unsupported:
                Label(
                    MoroL10n.NotificationSettings.policyUnsupported,
                    systemImage: "server.rack"
                )
                .foregroundStyle(theme.colors.textSecondary)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.colors.textSecondary)
                    Button(MoroL10n.Notifications.retryAction) {
                        guard let apiClient else { return }
                        Task { await policyController.refresh(using: apiClient) }
                    }
                }

            case .loaded:
                if let serverPolicy = policyController.policy {
                    policyRuleRow(
                        title: MoroL10n.NotificationSettings.notFollowing,
                        detail: MoroL10n.NotificationSettings.notFollowingDetail,
                        selection: policyBinding(\.forNotFollowing)
                    )
                    policyRuleRow(
                        title: MoroL10n.NotificationSettings.notFollowers,
                        detail: MoroL10n.NotificationSettings.notFollowersDetail,
                        selection: policyBinding(\.forNotFollowers)
                    )
                    policyRuleRow(
                        title: MoroL10n.NotificationSettings.newAccounts,
                        detail: MoroL10n.NotificationSettings.newAccountsDetail,
                        selection: policyBinding(\.forNewAccounts)
                    )
                    policyRuleRow(
                        title: MoroL10n.NotificationSettings.privateMentions,
                        detail: MoroL10n.NotificationSettings.privateMentionsDetail,
                        selection: policyBinding(\.forPrivateMentions)
                    )
                    policyRuleRow(
                        title: MoroL10n.NotificationSettings.limitedAccounts,
                        detail: MoroL10n.NotificationSettings.limitedAccountsDetail,
                        selection: policyBinding(\.forLimitedAccounts)
                    )
                    if serverPolicy.forBots != nil {
                        policyRuleRow(
                            title: MoroL10n.NotificationSettings.bots,
                            detail: MoroL10n.NotificationSettings.botsDetail,
                            selection: botsPolicyBinding
                        )
                    }

                    if let apiClient {
                        NavigationLink {
                            NotificationRequestsView(apiClient: apiClient) { request in
                                policyController.resolvePendingRequest(request)
                            }
                        } label: {
                            HStack {
                                Label(
                                    MoroL10n.NotificationSettings.requestsTitle,
                                    systemImage: "tray.full"
                                )
                                Spacer()
                                if serverPolicy.summary.pendingRequestsCount > 0 {
                                    Text("\(serverPolicy.summary.pendingRequestsCount)")
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.textSecondary)
                                }
                            }
                        }
                    }

                    if let refreshError = policyController.refreshError {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(refreshError, systemImage: "exclamationmark.triangle")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                            Button(MoroL10n.Notifications.retryAction) {
                                guard let apiClient else { return }
                                Task { await policyController.refresh(using: apiClient) }
                            }
                        }
                    }

                    if policyController.isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(MoroL10n.EditProfile.saving)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    } else if let saveError = policyController.saveError {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.error)
                    }
                }
            }
        } header: {
            HStack {
                MoroSettingsSectionHeader(title: MoroL10n.NotificationSettings.sectionIntake)
                Spacer()
                if policyController.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(MoroL10n.Timeline.refreshing)
                }
            }
        } footer: {
            Text(MoroL10n.NotificationSettings.intakeFooter)
        }
    }

    @ViewBuilder
    private var pushPreferencesSection: some View {
        Section {
            if PushRegistrationCenter.isPushCapabilityEnabled {
                Picker(
                    MoroL10n.NotificationSettings.receiveFrom,
                    selection: pushBinding(\.notificationPolicy)
                ) {
                    ForEach(AppSettings.NotificationPolicy.allCases, id: \.rawValue) { policy in
                        Text(policy.localizedName).tag(policy)
                    }
                }

                Toggle(
                    MoroL10n.NotificationSettings.typeMentions,
                    isOn: pushBinding(\.receiveMentionsAndReplies))
                    .accessibilityIdentifier("notificationSettings.push.mentions")
                Toggle(MoroL10n.NotificationSettings.typeBoosts, isOn: pushBinding(\.receiveBoosts))
                    .accessibilityIdentifier("notificationSettings.push.boosts")
                Toggle(
                    MoroL10n.NotificationSettings.typeFavourites,
                    isOn: pushBinding(\.receiveFavourites))
                    .accessibilityIdentifier("notificationSettings.push.favourites")
                Toggle(
                    MoroL10n.NotificationSettings.typeNewFollowers,
                    isOn: pushBinding(\.receiveNewFollowers))
                    .accessibilityIdentifier("notificationSettings.push.followers")

                if pushSync.savingSettings.contains(accountKey) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(MoroL10n.EditProfile.saving)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .accessibilityIdentifier("notificationSettings.push.saving")
                } else if pushSync.failedSettings.contains(accountKey) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(MoroL10n.NotificationSettings.pushSaveFailed, systemImage: "exclamationmark.circle")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.error)
                            .accessibilityIdentifier("notificationSettings.push.saveError")
                        Button {
                            guard let apiClient else { return }
                            pushSync.resumeSettings(apiClient: apiClient, sessionKey: accountKey)
                        } label: {
                            Text(MoroL10n.Notifications.retryAction)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("notificationSettings.push.retry")
                    }
                }

                if pushRegistration.authorizationStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(
                            MoroL10n.NotificationSettings.openSystemSettings,
                            systemImage: "bell.slash"
                        )
                        .foregroundStyle(theme.colors.textPrimary)
                    }
                }
            } else {
                Label(
                    MoroL10n.NotificationSettings.pushUnavailable,
                    systemImage: "bell.slash"
                )
                .foregroundStyle(theme.colors.textSecondary)
            }
        } header: {
            MoroSettingsSectionHeader(title: MoroL10n.NotificationSettings.sectionPush)
        } footer: {
            Text("\(MoroL10n.Settings.pushScope)\n\n\(MoroL10n.NotificationSettings.pushFooter)")
        }
    }

    private func policyRuleRow(
        title: String,
        detail: String,
        selection: Binding<ServerNotificationPolicy.Disposition>
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                ForEach(ServerNotificationPolicy.Disposition.allCases) { disposition in
                    Text(disposition.localizedName).tag(disposition)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(policyController.isSaving)
        }
    }

    private func policyBinding(
        _ keyPath: WritableKeyPath<ServerNotificationPolicy, ServerNotificationPolicy.Disposition>
    ) -> Binding<ServerNotificationPolicy.Disposition> {
        Binding(
            get: { policyController.policy?[keyPath: keyPath] ?? .accept },
            set: { value in
                guard let apiClient else { return }
                Task { await policyController.save(value, at: keyPath, using: apiClient) }
            }
        )
    }

    private var botsPolicyBinding: Binding<ServerNotificationPolicy.Disposition> {
        Binding(
            get: { policyController.policy?.forBots ?? .accept },
            set: { value in
                guard let apiClient else { return }
                Task { await policyController.saveBots(value, using: apiClient) }
            }
        )
    }

    private func pushBinding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = value
                guard let apiClient else { return }
                pushSync.saveSettings(.init(settings: settings), apiClient: apiClient, accountKey: accountKey)
            }
        )
    }
}

private extension ServerNotificationPolicy.Disposition {
    var localizedName: String {
        switch self {
        case .accept: return MoroL10n.NotificationSettings.policyAccept
        case .filter: return MoroL10n.NotificationSettings.policyFilter
        case .drop: return MoroL10n.NotificationSettings.policyDrop
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .moroTheme(MoroTheme())
}
