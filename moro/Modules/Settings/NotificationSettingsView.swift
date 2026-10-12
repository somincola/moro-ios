//
//  NotificationSettingsView.swift
//  moro
//
//  Server notification intake policy and this device's push preferences.
//

import SwiftUI
import UIKit

/// One page for everything notification-related: this device's push alerts first,
/// then the server-side intake rules. Reached from Settings and the Notifications tab.
struct NotificationSettingsView: View {
    @Environment(\.activeAccountKey) private var activeAccountKey

    let apiClient: MastodonAPI?

    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
    }

    var body: some View {
        NotificationSettingsContentView(
            apiClient: apiClient,
            accountKey: activeAccountKey
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

    /// Live client for server intake rules.
    let apiClient: MastodonAPI?
    /// Push sync keeps a credential snapshot so a save that outlives this page (or an
    /// account switch) still lands on the account that made the change.
    let pushClient: MastodonAPI?
    let accountKey: String

    init(apiClient: MastodonAPI?, accountKey: String) {
        self.apiClient = apiClient
        self.pushClient = (apiClient as? MastodonClient)?.sessionSnapshot() ?? apiClient
        self.accountKey = accountKey
        _policyController = StateObject(
            wrappedValue: NotificationPolicyController(accountKey: accountKey)
        )
    }

    var body: some View {
        List {
            pushPreferencesSection
            notificationIntakeSection
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome(separators: .visible)
        .textCase(nil)
        .navigationTitle(MoroL10n.NotificationSettings.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("notificationSettings.page")
        .task {
            if let pushClient, PushRegistrationCenter.isPushCapabilityEnabled {
                pushSync.resumeSettings(apiClient: pushClient, sessionKey: accountKey)
                await pushRegistration.refreshAuthorizationStatus()
            }
            guard let apiClient else {
                policyController.markUnsupported()
                return
            }
            await policyController.refresh(using: apiClient)
        }
        .onChange(of: pushRegistration.deviceTokenHex) { _, _ in
            guard let pushClient else { return }
            pushSync.resumeSettings(apiClient: pushClient, sessionKey: accountKey)
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
                        id: "notFollowing",
                        title: MoroL10n.NotificationSettings.notFollowing,
                        detail: MoroL10n.NotificationSettings.notFollowingDetail,
                        selection: policyBinding(\.forNotFollowing)
                    )
                    policyRuleRow(
                        id: "notFollowers",
                        title: MoroL10n.NotificationSettings.notFollowers,
                        detail: MoroL10n.NotificationSettings.notFollowersDetail,
                        selection: policyBinding(\.forNotFollowers)
                    )
                    policyRuleRow(
                        id: "newAccounts",
                        title: MoroL10n.NotificationSettings.newAccounts,
                        detail: MoroL10n.NotificationSettings.newAccountsDetail,
                        selection: policyBinding(\.forNewAccounts)
                    )
                    policyRuleRow(
                        id: "privateMentions",
                        title: MoroL10n.NotificationSettings.privateMentions,
                        detail: MoroL10n.NotificationSettings.privateMentionsDetail,
                        selection: policyBinding(\.forPrivateMentions)
                    )
                    policyRuleRow(
                        id: "limitedAccounts",
                        title: MoroL10n.NotificationSettings.limitedAccounts,
                        detail: MoroL10n.NotificationSettings.limitedAccountsDetail,
                        selection: policyBinding(\.forLimitedAccounts)
                    )
                    if serverPolicy.forBots != nil {
                        policyRuleRow(
                            id: "bots",
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
                NavigationLink {
                    PushSourceChoiceView(pushClient: pushClient, accountKey: accountKey)
                } label: {
                    LabeledContent(MoroL10n.NotificationSettings.receiveFrom) {
                        Text(settings.notificationPolicy.localizedName)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .accessibilityIdentifier("notificationSettings.push.receiveFrom")

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
                            guard let pushClient else { return }
                            pushSync.resumeSettings(apiClient: pushClient, sessionKey: accountKey)
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
            HStack {
                MoroSettingsSectionHeader(title: MoroL10n.NotificationSettings.sectionPush)
                Spacer()
            }
        } footer: {
            Text(MoroL10n.NotificationSettings.pushFooter)
        }
    }

    /// Rule summary row; the choice itself happens on a report-style page with
    /// a sentence for what each disposition actually does.
    private func policyRuleRow(
        id: String,
        title: String,
        detail: String,
        selection: Binding<ServerNotificationPolicy.Disposition>
    ) -> some View {
        NavigationLink {
            PolicyRuleChoiceView(
                controller: policyController,
                title: title,
                detail: detail,
                selection: selection
            )
        } label: {
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
                Text(selection.wrappedValue.localizedName)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .disabled(policyController.isSaving)
        .accessibilityIdentifier("notificationSettings.rule.\(id)")
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
                guard let pushClient else { return }
                pushSync.saveSettings(.init(settings: settings), apiClient: pushClient, accountKey: accountKey)
            }
        )
    }
}

private struct PolicyRuleChoiceView: View {
    @ObservedObject var controller: NotificationPolicyController
    let title: String
    let detail: String
    let selection: Binding<ServerNotificationPolicy.Disposition>

    var body: some View {
        MoroChoicePage(
            heading: title,
            hint: detail,
            footnote: MoroL10n.NotificationSettings.intakeFooter,
            errorMessage: controller.saveError,
            options: ServerNotificationPolicy.Disposition.allCases.map {
                MoroChoiceOption(value: $0, title: $0.localizedName, detail: $0.localizedDetail)
            },
            selection: selection.wrappedValue,
            isBusy: controller.isSaving,
            accessibilityPrefix: "notificationSettings.choice"
        ) { selection.wrappedValue = $0 }
    }
}

private struct PushSourceChoiceView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var pushSync = PushSubscriptionCoordinator.shared
    let pushClient: MastodonAPI?
    let accountKey: String

    var body: some View {
        MoroChoicePage(
            heading: MoroL10n.NotificationSettings.receiveFrom,
            hint: MoroL10n.NotificationSettings.receiveFromHint,
            footnote: MoroL10n.NotificationSettings.pushFooter,
            errorMessage: pushSync.failedSettings.contains(accountKey)
                ? MoroL10n.NotificationSettings.pushSaveFailed : nil,
            options: AppSettings.NotificationPolicy.allCases.map {
                MoroChoiceOption(value: $0, title: $0.localizedName)
            },
            selection: settings.notificationPolicy,
            accessibilityPrefix: "notificationSettings.push.source"
        ) { policy in
            settings.notificationPolicy = policy
            guard let pushClient else { return }
            pushSync.saveSettings(.init(settings: settings), apiClient: pushClient, accountKey: accountKey)
        }
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

    var localizedDetail: String {
        switch self {
        case .accept: return MoroL10n.NotificationSettings.policyAcceptDetail
        case .filter: return MoroL10n.NotificationSettings.policyFilterDetail
        case .drop: return MoroL10n.NotificationSettings.policyDropDetail
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .moroTheme(MoroTheme())
}
