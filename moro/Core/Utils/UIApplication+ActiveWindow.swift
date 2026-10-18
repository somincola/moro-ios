//
//  UIApplication+ActiveWindow.swift
//  moro
//

import UIKit

extension UIApplication {
    /// The key window of the scene the person is using right now.
    ///
    /// On a regular iPhone Moro only ever has one window, so "the first connected scene"
    /// or "any key window" happened to be right. On iPhone Duo the inner display can host
    /// several Moro windows side by side, and those shortcuts can pick the wrong one.
    /// Prefer the foreground-active scene, then a foreground-inactive one, then anything.
    var moroActiveKeyWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered =
            scenes.filter { $0.activationState == .foregroundActive }
            + scenes.filter { $0.activationState == .foregroundInactive }
            + scenes.filter {
                $0.activationState != .foregroundActive && $0.activationState != .foregroundInactive
            }
        for scene in ordered {
            if let window = scene.keyWindow { return window }
        }
        return ordered.first?.windows.first
    }

    /// The top-most presented view controller in `moroActiveKeyWindow`, for presenting
    /// UIKit sheets (share, players) from code that has no view of its own.
    ///
    /// - Parameter skippingDismissing: Stop below a controller that is mid-dismissal,
    ///   so a new presentation isn't attached to something that is going away.
    func moroTopViewController(skippingDismissing: Bool = true) -> UIViewController? {
        var top = moroActiveKeyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            if skippingDismissing && presented.isBeingDismissed { break }
            top = presented
        }
        return top
    }
}
