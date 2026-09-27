//
//  NotificationSettingsView.swift
//  moro
//
//  Server notification intake policy and this device's push preferences.
//

import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    private enum PolicyLoadState {
        case idle
        case loading
        case loaded
        case unsupported
        case failed(String)
    }

    @Environment(\.moroTheme) private var theme
    @StateObject private var settings = AppSettings.shared
    @StateObject private var pushRegistration = PushRegistrationCenter.shared

    let apiClient: MastodonAPI?

    @State private var policyLoadState: PolicyLoadState = .idle
    @State private var serverPolicy: ServerNotificationPolicy?
    @State private var isPolicySaving = false
    @State private var policySaveError: String?
    @State private var isPushSaving = false
    @State private var pushSubscription: PushSubscription?
    @State private var pushSyncDebounce: Task<Void, Never>?

    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
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
                policyLoadState = .unsupported
                return
            }
            async let policyLoad: Void = loadNotificationPolicy(apiClient: apiClient)
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
            switch policyLoadState {
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
                        Task { await loadNotificationPolicy(apiClient: apiClient) }
                    }
                }

            case .loaded:
                if let serverPolicy {
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
                                resolvePendingRequest(request)
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

                    if isPolicySaving {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(MoroL10n.EditProfile.saving)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    } else if let policySaveError {
                        Label(policySaveError, systemImage: "exclamationmark.circle")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.error)
                    }
                }
            }
        } header: {
            Text(MoroL10n.NotificationSettings.sectionIntake)
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
            .disabled(isPolicySaving)
        }
    }

    private func policyBinding(
        _ keyPath: WritableKeyPath<ServerNotificationPolicy, ServerNotificationPolicy.Disposition>
    ) -> Binding<ServerNotificationPolicy.Disposition> {
        Binding(
            get: { serverPolicy?[keyPath: keyPath] ?? .accept },
            set: { value in
                Task { await savePolicy(value, at: keyPath) }
            }
        )
    }

    private var botsPolicyBinding: Binding<ServerNotificationPolicy.Disposition> {
        Binding(
            get: { serverPolicy?.forBots ?? .accept },
            set: { value in
                Task { await saveBotsPolicy(value) }
            }
        )
    }

    @MainActor
    private func loadNotificationPolicy(apiClient: MastodonAPI) async {
        policyLoadState = .loading
        do {
            serverPolicy = try await apiClient.fetchNotificationPolicy()
            policyLoadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            if let status = (error as? APIError)?.httpStatusCode,
                [404, 405, 501].contains(status)
            {
                policyLoadState = .unsupported
            } else {
                policyLoadState = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func savePolicy(
        _ value: ServerNotificationPolicy.Disposition,
        at keyPath: WritableKeyPath<ServerNotificationPolicy, ServerNotificationPolicy.Disposition>
    ) async {
        guard let apiClient, let previous = serverPolicy, !isPolicySaving else { return }
        var updated = previous
        updated[keyPath: keyPath] = value
        await persistPolicy(updated, previous: previous, apiClient: apiClient)
    }

    @MainActor
    private func saveBotsPolicy(_ value: ServerNotificationPolicy.Disposition) async {
        guard let apiClient, let previous = serverPolicy, !isPolicySaving else { return }
        var updated = previous
        updated.forBots = value
        await persistPolicy(updated, previous: previous, apiClient: apiClient)
    }

    @MainActor
    private func persistPolicy(
        _ updated: ServerNotificationPolicy,
        previous: ServerNotificationPolicy,
        apiClient: MastodonAPI
    ) async {
        serverPolicy = updated
        policySaveError = nil
        isPolicySaving = true
        defer { isPolicySaving = false }
        do {
            serverPolicy = try await apiClient.updateNotificationPolicy(updated)
        } catch {
            serverPolicy = previous
            policySaveError = error.localizedDescription
        }
    }

    private func resolvePendingRequest(_ request: ServerNotificationRequest) {
        guard var policy = serverPolicy else { return }
        policy.summary = .init(
            pendingRequestsCount: max(0, policy.summary.pendingRequestsCount - 1),
            pendingNotificationsCount: max(
                0, policy.summary.pendingNotificationsCount - request.notificationsCount)
        )
        serverPolicy = policy
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
