//
//  NotificationSettingsView.swift
//  moro
//
//  Server notification intake policy and this device's push preferences.
//

import SwiftUI
import UIKit

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
    @StateObject private var policyController: NotificationPolicyController

    let apiClient: MastodonAPI?

    @State private var isPushSaving = false
    @State private var pushSubscription: PushSubscription?
    @State private var pushSyncDebounce: Task<Void, Never>?

    init(apiClient: MastodonAPI?, accountKey: String) {
        self.apiClient = apiClient
        _policyController = StateObject(
            wrappedValue: NotificationPolicyController(accountKey: accountKey)
        )
    }

    var body: some View {
        List {
            notificationIntakeSection
            pushPreferencesSection
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.NotificationSettings.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let apiClient else {
                policyController.markUnsupported()
                return
            }
            async let policyLoad: Void = policyController.refresh(using: apiClient)
            if PushRegistrationCenter.isPushCapabilityEnabled {
                await pushRegistration.refreshAuthorizationStatus()
                await loadPushSubscription(apiClient: apiClient)
            }
            await policyLoad
        }
        .onDisappear {
            pushSyncDebounce?.cancel()
        }
        .onChange(of: pushRegistration.deviceTokenHex) { _, _ in
            guard let apiClient else { return }
            Task { await loadPushSubscription(apiClient: apiClient) }
        }
        .onChange(of: pushServerSyncKey) { _, _ in
            schedulePushServerSync()
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
                Text(MoroL10n.NotificationSettings.sectionIntake)
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
                    selection: $settings.notificationPolicy
                ) {
                    ForEach(AppSettings.NotificationPolicy.allCases, id: \.rawValue) { policy in
                        Text(policy.localizedName).tag(policy)
                    }
                }

                Toggle(
                    MoroL10n.NotificationSettings.typeMentions,
                    isOn: $settings.receiveMentionsAndReplies)
                Toggle(MoroL10n.NotificationSettings.typeBoosts, isOn: $settings.receiveBoosts)
                Toggle(
                    MoroL10n.NotificationSettings.typeFavourites,
                    isOn: $settings.receiveFavourites)
                Toggle(
                    MoroL10n.NotificationSettings.typeNewFollowers,
                    isOn: $settings.receiveNewFollowers)

                if isPushSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(MoroL10n.EditProfile.saving)
                            .foregroundStyle(theme.colors.textSecondary)
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
            Text(MoroL10n.NotificationSettings.sectionPush)
        } footer: {
            Text(MoroL10n.NotificationSettings.pushFooter)
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

    // MARK: - Push server sync

    private var pushServerSyncKey: String {
        [
            settings.notificationPolicy.rawValue,
            String(settings.receiveMentionsAndReplies),
            String(settings.receiveBoosts),
            String(settings.receiveFavourites),
            String(settings.receiveNewFollowers),
        ].joined(separator: "|")
    }

    private func schedulePushServerSync() {
        guard let apiClient, pushSubscription != nil else { return }
        pushSyncDebounce?.cancel()
        pushSyncDebounce = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await syncPushSettings(apiClient: apiClient)
        }
    }

    private var pushPolicyValue: String {
        switch settings.notificationPolicy {
        case .anyone: return "all"
        case .followers: return "follower"
        case .followed: return "following"
        case .noone: return "none"
        }
    }

    private var desiredPushAlerts: PushSubscription.Alerts {
        PushSubscription.Alerts(
            mention: settings.receiveMentionsAndReplies,
            status: pushSubscription?.alerts.status ?? false,
            reblog: settings.receiveBoosts,
            follow: settings.receiveNewFollowers,
            followRequest: settings.receiveNewFollowers,
            favourite: settings.receiveFavourites,
            poll: pushSubscription?.alerts.poll ?? false,
            update: pushSubscription?.alerts.update ?? false,
            adminSignUp: pushSubscription?.alerts.adminSignUp ?? false,
            adminReport: pushSubscription?.alerts.adminReport ?? false
        )
    }

    @MainActor
    private func loadPushSubscription(apiClient: MastodonAPI) async {
        pushSubscription = try? await apiClient.fetchPushSubscription()
    }

    @MainActor
    private func syncPushSettings(apiClient: MastodonAPI) async {
        guard pushSubscription != nil, !isPushSaving else { return }
        isPushSaving = true
        defer { isPushSaving = false }
        do {
            pushSubscription = try await apiClient.updatePushSubscription(
                alerts: desiredPushAlerts,
                policy: pushPolicyValue
            )
        } catch {
            AppLogger.error("[Push] alert sync failed: \(error)")
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
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .moroTheme(MoroTheme())
}
