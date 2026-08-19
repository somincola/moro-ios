//
//  NotificationSettingsView.swift
//  moro
//
//  Notification settings: the in-app inbox filters double as the push alert
//  preferences. Push onboarding/binding is fully automatic
//  (PushSubscriptionCoordinator); this page only mirrors changes to the
//  server subscription and points at system settings when permission was
//  denied.
//

import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @Environment(\.moroTheme) private var theme
    @StateObject private var settings = AppSettings.shared
    @StateObject private var pushRegistration = PushRegistrationCenter.shared

    let apiClient: MastodonAPI?

    @State private var isPushSaving = false
    @State private var pushSubscription: PushSubscription?
    @State private var pushSyncDebounce: Task<Void, Never>?

    init(apiClient: MastodonAPI? = nil) {
        self.apiClient = apiClient
    }

    var body: some View {
        List {
            Section {
                Picker(
                    MoroL10n.NotificationSettings.receiveFrom,
                    selection: $settings.notificationPolicy
                ) {
                    ForEach(AppSettings.NotificationPolicy.allCases, id: \.rawValue) { policy in
                        Text(policy.localizedName).tag(policy)
                    }
                }
            } header: {
                Text(MoroL10n.NotificationSettings.sectionDisplay)
            }

            Section {
                Toggle(
                    MoroL10n.NotificationSettings.typeMentions,
                    isOn: $settings.receiveMentionsAndReplies)
                Toggle(MoroL10n.NotificationSettings.typeBoosts, isOn: $settings.receiveBoosts)
                Toggle(
                    MoroL10n.NotificationSettings.typeFavourites, isOn: $settings.receiveFavourites
                )
                Toggle(
                    MoroL10n.NotificationSettings.typeNewFollowers,
                    isOn: $settings.receiveNewFollowers)
            } header: {
                Text(MoroL10n.NotificationSettings.sectionType)
            }

            // Push is automatic; the only state worth surfacing here is a
            // denied permission, which can only be fixed in system settings.
            if PushRegistrationCenter.isPushCapabilityEnabled,
                pushRegistration.authorizationStatus == .denied
            {
                Section {
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
                } header: {
                    Text(MoroL10n.NotificationSettings.sectionPush)
                }
            }
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.NotificationSettings.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let apiClient, PushRegistrationCenter.isPushCapabilityEnabled else { return }
            await pushRegistration.refreshAuthorizationStatus()
            await loadPushSubscription(apiClient: apiClient)
        }
        .onChange(of: pushRegistration.deviceTokenHex) { _, _ in
            guard let apiClient else { return }
            Task { await loadPushSubscription(apiClient: apiClient) }
        }
        .onChange(of: notificationServerSyncKey) { _, _ in
            scheduleNotificationServerSync()
        }
    }

    // MARK: - Server sync

    /// Composite of the server-synced notification controls; drives the debounced
    /// onChange above so an inline toggle/policy change reaches the server.
    private var notificationServerSyncKey: String {
        [
            settings.notificationPolicy.rawValue,
            String(settings.receiveMentionsAndReplies),
            String(settings.receiveBoosts),
            String(settings.receiveFavourites),
            String(settings.receiveNewFollowers),
        ].joined(separator: "|")
    }

    /// Push the inline notification toggles / policy picker to the server, debounced
    /// so flipping several in a row issues one request. No-op until a push
    /// subscription exists (in-app filtering still applies immediately regardless).
    private func scheduleNotificationServerSync() {
        guard let apiClient, pushSubscription != nil else { return }
        pushSyncDebounce?.cancel()
        pushSyncDebounce = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await syncPushSettings(apiClient: apiClient)
        }
    }

    private var pushPolicyValue: String {
        switch settings.notificationPolicy {
        case .anyone:
            return "all"
        case .followers:
            return "follower"
        case .followed:
            return "following"
        case .noone:
            return "none"
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
        guard pushSubscription != nil else { return }
        guard !isPushSaving else { return }

        isPushSaving = true
        defer { isPushSaving = false }

        do {
            pushSubscription = try await apiClient.updatePushSubscription(
                alerts: desiredPushAlerts,
                policy: pushPolicyValue
            )
        } catch {
            // Silent: in-app filtering already applied; the next toggle change
            // or launch retries the server sync.
            AppLogger.error("[Push] alert sync failed: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .moroTheme(MoroTheme())
}
