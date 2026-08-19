//
//  PushRegistrationCenter.swift
//  moro
//
//  Manages APNs authorization and device token lifecycle.
//

import Foundation
import UIKit
import UserNotifications
import Combine

@MainActor
final class PushRegistrationCenter: NSObject, ObservableObject {
    static let shared = PushRegistrationCenter()

    /// Whether the app currently ships a usable APNs push capability.
    ///
    /// `true` now that the `aps-environment` entitlement is present
    /// (`development` in `moro.entitlements`, `production` in
    /// `moroRelease.entitlements`) and the App ID `com.somincola.moro` is
    /// registered on the developer portal with Push Notifications enabled.
    ///
    /// This gates two things: the push section in `NotificationSettingsView` and
    /// `registerForRemoteNotifications()` below. If signing ever ships without the
    /// entitlement again (so `registerForRemoteNotifications()` would fail with
    /// `no valid 'aps-environment' entitlement string found`), flip this back to
    /// `false` and remove the entitlement together.
    static let isPushCapabilityEnabled = true

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceTokenHex: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isRegisteringRemoteNotifications: Bool = false
    @Published private(set) var lastTokenUpdatedAt: Date?

    private let userDefaults = UserDefaults.standard
    private let tokenStorageKey = "push_device_token_hex"
    private let tokenUpdatedAtKey = "push_device_token_updated_at"

    override init() {
        super.init()
        deviceTokenHex = userDefaults.string(forKey: tokenStorageKey)
        lastTokenUpdatedAt = userDefaults.object(forKey: tokenUpdatedAtKey) as? Date
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationAndRegister() async {
        lastErrorMessage = nil
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            guard granted else {
                lastErrorMessage = MoroL10n.Push.permissionDenied
                return
            }
            registerForRemoteNotifications()
        } catch {
            lastErrorMessage = MoroL10n.Push.permissionFailed
        }
    }

    func registerForRemoteNotifications() {
        // Backstop: never hit APNs while the capability is off (no entitlement),
        // even if some path other than the (hidden) settings button calls this.
        guard Self.isPushCapabilityEnabled else { return }
        isRegisteringRemoteNotifications = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDidRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        isRegisteringRemoteNotifications = false
        lastErrorMessage = nil

        deviceTokenHex = token
        lastTokenUpdatedAt = Date()

        userDefaults.set(token, forKey: tokenStorageKey)
        userDefaults.set(lastTokenUpdatedAt, forKey: tokenUpdatedAtKey)
    }

    func handleDidFailToRegisterForRemoteNotifications(error: Error) {
        isRegisteringRemoteNotifications = false
        lastErrorMessage = error.localizedDescription
        AppFeedbackCenter.shared.showError(MoroL10n.Push.registrationFailed)
    }

    // MARK: - Relay endpoint

    /// Base URL of the self-hosted Web Push → APNs relay (moro-push-relay).
    static let relayBaseURL = "https://push.somincola.org"

    /// The Web Push endpoint handed to the Mastodon instance: the relay wraps
    /// the still-encrypted payload into an APNs push for this device. Debug
    /// builds are signed with the development aps-environment, so they must
    /// route through APNs' development gateway.
    ///
    /// `sessionKey` is carried as an opaque path suffix the relay echoes back
    /// in the notification (`x`), so a tap can later route to the right account.
    static func relayEndpointURL(deviceTokenHex: String, sessionKey: String?) -> String {
        #if DEBUG
            let environment = "development"
        #else
            let environment = "production"
        #endif
        var url = "\(relayBaseURL)/relay-to/\(environment)/\(deviceTokenHex)"
        if let sessionKey, !sessionKey.isEmpty,
            let encoded = sessionKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        {
            url += "/\(encoded)"
        }
        return url
    }
}

extension PushRegistrationCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let shouldPresent = await NotificationUnreadStore.shared.receiveRemoteNotification(
            userInfo: notification.request.content.userInfo
        )
        return shouldPresent ? [.banner, .list, .sound] : []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationUnreadStore.shared.handleNotificationResponse(
            userInfo: response.notification.request.content.userInfo
        )
    }
}
