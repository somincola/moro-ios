import XCTest

/// One-time hints. Every other UI test runs with hints hidden; these ask to see them.
@MainActor
final class TipsUITests: XCTestCase {
    func testHomeTabExplainsRetapToRefreshAndStaysOutOfTheWay() {
        let app = launch(showingTips: true)
        defer { app.terminate() }
        let tip = app.staticTexts["再点一下首页也能刷新"]
        XCTAssertTrue(tip.waitForExistence(timeout: 10), "The hint points at the Home tab")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "在顶部时再点一下")).firstMatch.exists)
        attach(app, "tip-tab-retap-refresh")

        // Leaving Home takes it away; it belongs to the Home tab.
        app.buttons["mainTab.explore"].tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 5))
    }

    func testOtherUITestsNeverSeeHints() {
        let app = launch(showingTips: false)
        defer { app.terminate() }
        XCTAssertFalse(app.staticTexts["再点一下首页也能刷新"].waitForExistence(timeout: 3))
    }

    private func launch(showingTips: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TIMELINE_LIVE", "UITEST_TIMELINE_SWITCHING",
            "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITEST_TIMELINE_CONTROL_SOURCE"] = "home"
        if showingTips { app.launchEnvironment["UITEST_SHOW_TIPS"] = "1" }
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.buttons["mainTab.home"].waitForExistence(timeout: 15))
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
