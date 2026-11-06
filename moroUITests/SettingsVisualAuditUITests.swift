import XCTest

/// Captures each settings page in light and dark (one test per page, so one
/// flaky XCTest crash costs a single page). Screenshots only; no assertions
/// beyond reaching the page.
@MainActor
final class SettingsVisualAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    func testPage00_home() { capture("00-home", []) }
    func testPage01_account() { capture("01-account", ["settings.accounts"]) }
    func testPage02_display() { capture("02-display", ["settings.display"]) }
    func testPage03_reading() { capture("03-reading", ["settings.reading"]) }
    func testPage04_translation() { capture("04-translation", ["settings.reading", "settings.translation"]) }
    func testPage05_sensitive() { capture("05-sensitive", ["settings.reading", "settings.sensitiveMedia"]) }
    func testPage06_posting() { capture("06-posting", ["settings.posting"]) }
    func testPage07_visibility() { capture("07-visibility", ["settings.posting", "settings.defaultVisibility"]) }
    func testPage08_notifications() { capture("08-notifications", ["settings.notifications"]) }
    func testPage09_privacy() { capture("09-privacy", ["settings.privacy"]) }
    func testPage10_content() { capture("10-content", ["settings.contentSafety"]) }
    func testPage11_filters() { capture("11-filters", ["settings.contentSafety", "settings.filters"]) }
    func testPage12_storage() { capture("12-storage", ["settings.storage"]) }
    func testPage13_feedback() { capture("13-feedback", ["settings.feedback"]) }
    func testPage14_about() { capture("14-about", ["settings.about"]) }
    func testPage15_server() { capture("15-server", ["settings.accounts", "settings.server"]) }
    func testPage16_delete() { capture("16-delete", ["settings.accounts", "settings.accountActions"]) }
    func testPage17_profile() { capture("17-profile", ["settings.accounts", "settings.profile"]) }
    func testPage18_appicon() { capture("18-appicon", ["settings.display", "settings.appIcon"]) }
    func testPage19_language() { capture("19-language", ["settings.posting", "settings.postLanguage"]) }
    func testPage20_licenses() { capture("20-licenses", ["settings.about", "about.licenses"]) }
    func testPage22_serverRules() { capture("22-server-rules", ["settings.accounts", "settings.server", "规则"]) }

    private func capture(_ name: String, _ path: [String]) {
        for dark in [false, true] {
            let app = launch(dark: dark)
            let scheme = dark ? "dark" : "light"
            var reached = true
            for id in path where reached {
                reached = open(id, app)
                sleep(1)
            }
            if reached {
                shot(app, "\(name)-\(scheme)")
                app.swipeUp()
                shot(app, "\(name)-\(scheme)-scrolled")
            } else {
                XCTFail("could not reach \(name)")
            }
            app.terminate()
        }
    }

    private func launch(dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SETTINGS_SHEET", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_SETTINGS_SHEET"] = "1"
        app.launchEnvironment["UITEST_SETTINGS_ACCOUNT"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func open(_ id: String, _ app: XCUIApplication) -> Bool {
        // Settings entries are buttons (links, rows). Querying `.any` makes the
        // automation runtime fetch an identifier for every element, and that
        // logging volume gets the app's log client quarantined and crashed.
        var element = app.buttons[id]
        if !element.waitForExistence(timeout: 3) {
            element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            _ = element.waitForExistence(timeout: 2)
        }
        // Only swipe down while the target is above the fold; at the top a
        // downward swipe would dismiss the settings sheet.
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeDown() }
        guard element.exists, element.isHittable else { return false }
        element.tap()
        return true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
