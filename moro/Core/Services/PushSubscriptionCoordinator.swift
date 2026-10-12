//
//  PushSubscriptionCoordinator.swift
//  moro
//
//  Standard app push onboarding: when the main UI appears (login, restore or
//  account switch), ask for notification permission once, register with APNs
//  on grant, and bind the Web Push subscription to the active account as soon
//  as the device token is known. The diagnostics page in settings remains the
//  manual repair surface; this coordinator just makes the happy path automatic.
//

import Combine
import Foundation
import UserNotifications

@MainActor
final class PushSubscriptionCoordinator: ObservableObject {
    nonisolated deinit {}
    static let shared = PushSubscriptionCoordinator()

    struct Preferences: Codable, Equatable {
        var policy: String
        var mentions: Bool
        var boosts: Bool
        var favourites: Bool
        var followers: Bool

        init(settings: AppSettings) {
            switch settings.notificationPolicy {
            case .anyone: policy = "all"
            case .followers: policy = "follower"
            case .followed: policy = "following"
            case .noone: policy = "none"
            }
            mentions = settings.receiveMentionsAndReplies
            boosts = settings.receiveBoosts
            favourites = settings.receiveFavourites
            followers = settings.receiveNewFollowers
        }

        func applying(to alerts: PushSubscription.Alerts) -> PushSubscription.Alerts {
            var alerts = alerts
            alerts.mention = mentions
            alerts.reblog = boosts
            alerts.favourite = favourites
            alerts.follow = followers
            alerts.followRequest = followers
            return alerts
        }
    }

    @Published private(set) var savingSettings = Set<String>()
    @Published private(set) var failedSettings = Set<String>()
    private static let pendingSettingsKey = "push_pending_settings_v1"
    private let userDefaults: UserDefaults
    private var pendingSettings: [String: Preferences]
    private var syncedSettings: [String: Preferences] = [:]
    private var settingsTasks: [String: Task<Void, Never>] = [:]
    private var settingsWorkIDs: [String: UUID] = [:]

    private var tokenCancellable: AnyCancellable?
    /// "sessionKey|deviceToken" pairs already verified against the server this
    /// launch, so repeated activations (tab switches, account switches back)
    /// don't re-hit /push/subscription.
    private var ensuredKeys = Set<String>()
    private var ensuringKeys = Set<String>()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        pendingSettings = userDefaults.data(forKey: Self.pendingSettingsKey)
            .flatMap { try? JSONDecoder().decode([String: Preferences].self, from: $0) } ?? [:]
    }

    func saveSettings(_ preferences: Preferences, apiClient: MastodonAPI, accountKey: String) {
        pendingSettings[accountKey] = preferences
        persistPendingSettings()
        failedSettings.remove(accountKey)
        resumeSettings(apiClient: apiClient, sessionKey: accountKey)
    }

    func resumeSettings(apiClient: MastodonAPI, sessionKey: String?) {
        guard let key = sessionKey, pendingSettings[key] != nil, settingsTasks[key] == nil else { return }
        let client: MastodonAPI = (apiClient as? MastodonClient)?.sessionSnapshot() ?? apiClient
        let workID = UUID()
        settingsWorkIDs[key] = workID
        savingSettings.insert(key)
        failedSettings.remove(key)
        // Owned by the coordinator, so popping Settings never cancels a pending save.
        settingsTasks[key] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.settingsWorkIDs[key] == workID {
                    self.settingsTasks.removeValue(forKey: key)
                    self.settingsWorkIDs.removeValue(forKey: key)
                    self.savingSettings.remove(key)
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(600))
                while let preferences = self.pendingSettings[key] {
                    let subscription = try await client.fetchPushSubscription()
                    try Task.checkCancellation()
                    _ = try await client.updatePushSubscription(
                        alerts: preferences.applying(to: subscription.alerts), policy: preferences.policy)
                    try Task.checkCancellation()
                    self.syncedSettings[key] = preferences
                    if self.pendingSettings[key] == preferences {
                        self.pendingSettings.removeValue(forKey: key)
                        self.persistPendingSettings()
                    }
                }
            } catch {
                guard !Task.isCancelled, self.settingsWorkIDs[key] == workID else { return }
                self.failedSettings.insert(key)
                AppLogger.error("[Push] settings sync failed: \(error)")
                AppFeedbackCenter.shared.showError(MoroL10n.NotificationSettings.pushSaveFailed)
            }
        }
    }

    func removeSettings(for accountKey: String) {
        settingsWorkIDs.removeValue(forKey: accountKey)
        settingsTasks.removeValue(forKey: accountKey)?.cancel()
        pendingSettings.removeValue(forKey: accountKey)
        syncedSettings.removeValue(forKey: accountKey)
        savingSettings.remove(accountKey)
        failedSettings.remove(accountKey)
        persistPendingSettings()
    }

    private func persistPendingSettings() {
        if pendingSettings.isEmpty {
            userDefaults.removeObject(forKey: Self.pendingSettingsKey)
        } else if let data = try? JSONEncoder().encode(pendingSettings) {
            userDefaults.set(data, forKey: Self.pendingSettingsKey)
        }
    }

    /// Called whenever the app lands on the main UI for a session.
    func activate(apiClient: MastodonAPI, sessionKey: String?) {
        guard PushRegistrationCenter.isPushCapabilityEnabled else { return }
        let apiClient: MastodonAPI = (apiClient as? MastodonClient)?.sessionSnapshot() ?? apiClient
        resumeSettings(apiClient: apiClient, sessionKey: sessionKey)
        let registration = PushRegistrationCenter.shared

        // Re-arm the token observer against the session's client. The token
        // usually arrives (or is already cached) right after registration.
        tokenCancellable = registration.$deviceTokenHex
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] token in
                guard let self else { return }
                Task {
                    await self.ensureSubscription(
                        apiClient: apiClient, sessionKey: sessionKey, deviceToken: token)
                }
            }

        Task {
            await registration.refreshAuthorizationStatus()
            switch registration.authorizationStatus {
            case .notDetermined:
                // First launch: the system permission alert.
                await registration.requestAuthorizationAndRegister()
            case .authorized, .provisional, .ephemeral:
                // Permission already granted: refresh the APNs token silently.
                registration.registerForRemoteNotifications()
            default:
                // Denied — never nag. The push diagnostics page explains how
                // to re-enable from system settings.
                break
            }
        }
    }

    func ensureSubscription(
        apiClient: MastodonAPI, sessionKey: String?, deviceToken: String
    ) async {
        let key = "\(sessionKey ?? "-")|\(deviceToken)"
        guard !ensuredKeys.contains(key), !ensuringKeys.contains(key) else { return }
        ensuringKeys.insert(key)
        defer { ensuringKeys.remove(key) }

        let expectedEndpoint = PushRegistrationCenter.relayEndpointURL(
            deviceTokenHex: deviceToken, sessionKey: sessionKey)

        // Already bound to this device? Nothing to do.
        if let existing = try? await apiClient.fetchPushSubscription(),
            existing.endpoint == expectedEndpoint
        {
            ensuredKeys.insert(key)
            resumeSettings(apiClient: apiClient, sessionKey: sessionKey)
            return
        }

        // Missing, or pointing at a stale token/relay: (re)create. Mastodon's
        // POST replaces any previous subscription for this token.
        do {
            let preferences = sessionKey.flatMap { pendingSettings[$0] ?? syncedSettings[$0] }
            _ = try await apiClient.createPushSubscription(
                endpoint: expectedEndpoint,
                p256dh: try WebPushKeyStore.publicKeyBase64URL(),
                auth: try WebPushKeyStore.authSecretBase64URL(),
                alerts: preferences?.applying(to: .standardDefaults) ?? .standardDefaults,
                policy: preferences?.policy ?? "all"
            )
            ensuredKeys.insert(key)
            // Recreating a subscription can finish after a settings PUT; reapply the latest choice.
            if let sessionKey, let latest = pendingSettings[sessionKey] ?? syncedSettings[sessionKey] {
                saveSettings(latest, apiClient: apiClient, accountKey: sessionKey)
            }
        } catch {
            // Quietly retried on next launch/activation; the diagnostics page
            // surfaces the state for manual repair.
            AppLogger.error("[Push] automatic subscription failed: \(error)")
        }
    }
}

extension PushSubscription.Alerts {
    /// Defaults for a fresh automatic subscription: the interaction types a
    /// typical client notifies about, with noisy/admin ones off.
    static var standardDefaults: PushSubscription.Alerts {
        PushSubscription.Alerts(
            mention: true,
            status: false,
            reblog: true,
            follow: true,
            followRequest: true,
            favourite: true,
            poll: true,
            update: false,
            adminSignUp: false,
            adminReport: false
        )
    }
}
