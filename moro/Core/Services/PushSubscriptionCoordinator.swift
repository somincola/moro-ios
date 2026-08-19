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
final class PushSubscriptionCoordinator {
    static let shared = PushSubscriptionCoordinator()

    private var tokenCancellable: AnyCancellable?
    /// "sessionKey|deviceToken" pairs already verified against the server this
    /// launch, so repeated activations (tab switches, account switches back)
    /// don't re-hit /push/subscription.
    private var ensuredKeys = Set<String>()
    private var isEnsuring = false

    private init() {}

    /// Called whenever the app lands on the main UI for a session.
    func activate(apiClient: MastodonAPI, sessionKey: String?) {
        guard PushRegistrationCenter.isPushCapabilityEnabled else { return }
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

    private func ensureSubscription(
        apiClient: MastodonAPI, sessionKey: String?, deviceToken: String
    ) async {
        let key = "\(sessionKey ?? "-")|\(deviceToken)"
        guard !ensuredKeys.contains(key), !isEnsuring else { return }
        isEnsuring = true
        defer { isEnsuring = false }

        let expectedEndpoint = PushRegistrationCenter.relayEndpointURL(
            deviceTokenHex: deviceToken, sessionKey: sessionKey)

        // Already bound to this device? Nothing to do.
        if let existing = try? await apiClient.fetchPushSubscription(),
            existing.endpoint == expectedEndpoint
        {
            ensuredKeys.insert(key)
            return
        }

        // Missing, or pointing at a stale token/relay: (re)create. Mastodon's
        // POST replaces any previous subscription for this token.
        do {
            _ = try await apiClient.createPushSubscription(
                endpoint: expectedEndpoint,
                p256dh: try WebPushKeyStore.publicKeyBase64URL(),
                auth: try WebPushKeyStore.authSecretBase64URL(),
                alerts: .standardDefaults,
                policy: "all"
            )
            ensuredKeys.insert(key)
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
