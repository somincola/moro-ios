//
//  PrivacySnapshotShield.swift
//  moro
//
//  Blurs the app before iOS saves its app-switcher snapshot.
//

import UIKit

/// Covers each window with a blur when its scene goes to the background, and removes it when
/// the scene comes back.
///
/// It reacts to the background only, as Apple's QA1838 recommends: iOS takes the app-switcher
/// snapshot right after the scene enters the background, so the cover must already be in the
/// window by then, added synchronously. Notification Center, Control Center, system alerts and
/// the moment of swiping into the switcher only make the scene inactive; they leave Moro
/// untouched, as other apps do.
@MainActor
final class PrivacySnapshotShield {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = PrivacySnapshotShield()

    /// Tag of the cover view, so it can be found again and never stacks.
    static let coverTag = 0x5052_5653 // "PRVS"

    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Starts watching every scene. Safe to call more than once.
    func install(notificationCenter: NotificationCenter = .default) {
        guard observers.isEmpty else { return }
        observers = [
            notificationCenter.addObserver(
                forName: UIScene.didEnterBackgroundNotification, object: nil, queue: nil
            ) { notification in
                let scene = notification.object as? UIWindowScene
                // Posted on the main thread inside the scene's background callback; covering
                // synchronously here lands before the snapshot.
                MainActor.assumeIsolated {
                    if let scene { PrivacySnapshotShield.shared.cover(scene.windows) }
                }
            },
            notificationCenter.addObserver(
                forName: UIScene.willEnterForegroundNotification, object: nil, queue: nil
            ) { notification in
                let scene = notification.object as? UIWindowScene
                MainActor.assumeIsolated {
                    if let scene { PrivacySnapshotShield.shared.uncover(scene.windows) }
                }
            },
        ]
    }

    func cover(_ windows: [UIWindow]) {
        for window in windows where !window.isHidden && window.viewWithTag(Self.coverTag) == nil {
            let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
            cover.tag = Self.coverTag
            cover.frame = window.bounds
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cover.isUserInteractionEnabled = false
            cover.accessibilityElementsHidden = true
            window.addSubview(cover)
            window.layoutIfNeeded()
        }
    }

    func uncover(_ windows: [UIWindow]) {
        for window in windows {
            window.viewWithTag(Self.coverTag)?.removeFromSuperview()
        }
    }
}
