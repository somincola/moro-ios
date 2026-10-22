//
//  MoroAppDelegate.swift
//  moro
//
//  UIApplicationDelegate bridge for APNs device token callbacks.
//

import UIKit

final class MoroAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushRegistrationCenter.shared.configure()
        PrivacySnapshotShield.shared.install()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistrationCenter.shared.handleDidRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushRegistrationCenter.shared.handleDidFailToRegisterForRemoteNotifications(error: error)
        }
    }
}
