import XCTest

final class ListOfflineCacheUITests: XCTestCase {
    @MainActor func testListOfflineCacheInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testListOfflineCacheInDarkMode() { verifyFlow(scheme: "dark") }

    @MainActor private func verifyFlow(scheme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_LIST_CACHE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launchEnvironment["UITEST_LIST_RESET"] = "1"
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        for (id, name, other) in [("alpha", "甲", "乙"), ("beta", "乙", "甲")] {
            open(id, app: app)
            XCTAssertTrue(body(name, app: app).waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(body(other, app: app).exists)
            app.navigationBars.buttons["测试列表"].tap()
        }
        app.terminate()
        app.launchEnvironment["UITEST_LIST_RESET"] = "0"
        app.launchEnvironment["UITEST_LIST_OFFLINE"] = "1"
        app.launch(isolatedFor: self)
        for (id, name, other) in [("alpha", "甲", "乙"), ("beta", "乙", "甲")] {
            open(id, app: app)
            XCTAssertTrue(app.buttons["timeline.cacheRetry"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(body(name, app: app).exists)
            XCTAssertFalse(body(other, app: app).exists)
            app.buttons["timeline.cacheRetry"].tap()
            XCTAssertTrue(body(name, app: app).exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "list-cache-\(id)-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.navigationBars.buttons["测试列表"].tap()
        }
    }
    @MainActor private func open(_ id: String, app: XCUIApplication) {
        let link = app.buttons["listCache.open.\(id)"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
    }
    @MainActor private func body(_ name: String, app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\(name)列表独立正文")).firstMatch
    }
}
