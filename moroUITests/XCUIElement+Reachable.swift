import XCTest

extension XCUIElement {
    /// `isHittable`, but true for SwiftUI `Menu` controls that a person can tap.
    ///
    /// On the current runtimes a `Menu` (the profile ⋯ button, the bookmark actions) reports
    /// `isHittable == false` even when nothing covers it and a tap at its center opens it:
    /// the accessibility hit test lands on a wrapper rather than the button itself. So an
    /// element also counts when its wrapper is hittable, when it sits in a navigation bar,
    /// or when its center is on screen between the navigation bar and the tab bar.
    @MainActor func isReachable(in app: XCUIApplication) -> Bool {
        if isHittable { return true }
        guard exists else { return false }
        if !identifier.isEmpty, app.otherElements[identifier].firstMatch.isHittable { return true }

        let frame = self.frame
        guard !frame.isEmpty else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let window = app.windows.firstMatch.frame
        guard window.contains(center) else { return false }

        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists, navigationBar.frame.contains(center) { return true }
        let contentTop = navigationBar.exists ? navigationBar.frame.maxY : window.minY
        let tabBar = app.tabBars.firstMatch
        let contentBottom = tabBar.exists ? tabBar.frame.minY : window.maxY
        return center.y > contentTop && center.y < contentBottom
    }
}
