import Testing
import UIKit
@testable import moro

@Suite(.serialized)
@MainActor
struct UIKitAvatarVisibilityTests {
    @Test func avatarVisibilityUsesItsOwnBoundsAndTheClippingScrollViewport() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 500)
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 100, width: 320, height: 200))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 320, height: 1000)
        window.rootViewController?.view.addSubview(scroll)
        let visibility = UIKitScrollVisibility()
        let avatar = UIKitScrollVisibilityProbeView(visibility: visibility)
        avatar.frame = CGRect(x: 16, y: 172, width: 44, height: 44)
        var changes: [Bool] = []
        avatar.onChange = { changes.append($0) }
        scroll.addSubview(avatar)
        window.layoutIfNeeded()
        visibility.refresh()
        try await wait { changes.last == true } // 28 / 44 is above the shared 60% threshold.

        scroll.contentOffset.y = -2
        visibility.refresh()
        try await wait { changes.last == false } // 26 / 44 is below it, although the row remains visible.
        scroll.contentOffset.y = 100
        visibility.refresh()
        try await wait { changes.last == true }
        scroll.isHidden = true
        visibility.refresh()
        try await wait { changes.last == false }
        scroll.isHidden = false
        visibility.refresh()
        try await wait { changes.last == true }
        avatar.removeFromSuperview()
        try await wait { changes.last == false }
    }

    @Test func detachingAnAvatarCancelsItsQueuedVisibleNotification() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let visibility = UIKitScrollVisibility()
        let avatar = UIKitScrollVisibilityProbeView(visibility: visibility)
        avatar.frame = CGRect(x: 20, y: 100, width: 44, height: 44)
        var becameVisible = false
        avatar.onChange = { becameVisible = becameVisible || $0 }
        window.rootViewController?.view.addSubview(avatar)
        visibility.refresh()
        avatar.detach()
        avatar.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!becameVisible)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
