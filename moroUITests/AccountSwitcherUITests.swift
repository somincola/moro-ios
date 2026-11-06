import XCTest

/// Touch and hold the Me tab to switch accounts.
@MainActor
final class AccountSwitcherUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHoldAndReleaseKeepsPanelOpenForATap() {
        for dark in [false, true] {
            let app = launch(dark: dark)
            let scheme = dark ? "dark" : "light"
            let me = meTab(app)
            me.press(forDuration: 0.6)

            let current = app.descendants(matching: .any)["accountSwitcher.account.push-a"]
            XCTAssertTrue(current.waitForExistence(timeout: 3))
            XCTAssertTrue(current.isSelected, "The active account is marked")
            XCTAssertTrue(app.descendants(matching: .any)["accountSwitcher.account.push-b"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["accountSwitcher.add"].exists)
            attach(app, "switcher-open-\(scheme)")

            app.descendants(matching: .any)["accountSwitcher.account.push-c"].tap()
            XCTAssertTrue(me.waitForExistence(timeout: 5))
            sleep(2)
            attach(app, "switcher-after-switch-\(scheme)")

            // The new account is now the current one.
            me.press(forDuration: 0.6)
            let switched = app.descendants(matching: .any)["accountSwitcher.account.push-c"]
            XCTAssertTrue(switched.waitForExistence(timeout: 3))
            XCTAssertTrue(switched.isSelected)
            app.terminate()
        }
    }

    func testSlideAlongTheBarAndReleaseSwitches() {
        let app = launch(dark: false)
        defer { app.terminate() }
        let me = meTab(app)
        // Find the most recent other account first: one avatar along from the current one
        // over a bottom bar, and further out beside iPhone Duo's vertical bar.
        let start = me.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        me.press(forDuration: 0.6)
        let next = app.descendants(matching: .any)["accountSwitcher.account.push-c"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        let dx = next.frame.midX - start.screenPoint.x
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 3))

        // Then hold the Me tab, slide onto it and release.
        start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
        XCTAssertTrue(me.waitForExistence(timeout: 5))
        sleep(2)

        me.press(forDuration: 0.6)
        // push-c was used most recently of the other accounts, so it sits next to the current one.
        let switched = app.descendants(matching: .any)["accountSwitcher.account.push-c"]
        XCTAssertTrue(switched.waitForExistence(timeout: 3))
        XCTAssertTrue(switched.isSelected, "Sliding left by one avatar picks the most recent other account")
    }

    func testTapOutsideOrOnCurrentAccountJustCloses() {
        let app = launch(dark: false)
        defer { app.terminate() }
        let me = meTab(app)
        me.press(forDuration: 0.6)
        let current = app.descendants(matching: .any)["accountSwitcher.account.push-a"]
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(current.waitForNonExistence(timeout: 3))

        me.press(forDuration: 0.6)
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        current.tap()
        XCTAssertTrue(current.waitForNonExistence(timeout: 3))
        me.press(forDuration: 0.6)
        XCTAssertTrue(app.descendants(matching: .any)["accountSwitcher.account.push-a"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["accountSwitcher.account.push-a"].isSelected)
    }

    func testMeTabStillSelectsOnATap() {
        let app = launch(dark: false)
        defer { app.terminate() }
        let me = meTab(app)
        me.tap()
        XCTAssertTrue(me.wait(for: \.isSelected, toEqual: true, timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["accountSwitcher.add"].exists)
    }

    private func launch(dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PUSH_OPEN", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_PUSH_SCENARIO"] = "inbox"
        app.launchEnvironment["UITEST_SWITCHER_ACCOUNTS"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launch(isolatedFor: self)
        return app
    }

    private func meTab(_ app: XCUIApplication) -> XCUIElement {
        // Any button, not just tab bar buttons: on iPhone Duo the tabs sit in a vertical
        // system bar that accessibility reports as a toolbar.
        let me = app.buttons["mainTab.me"]
        XCTAssertTrue(me.waitForExistence(timeout: 10))
        return me
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
