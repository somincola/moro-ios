import XCTest

final class ThreadReadingUITests: XCTestCase {
    @MainActor func testThreadReadingInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testThreadReadingInDarkMode() { verifyFlow(scheme: "dark") }

    @MainActor private func verifyFlow(scheme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_THREAD_READING", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["thread.readingOptions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        let branch = app.buttons["thread.branch.a"]
        reveal(branch, app: app)
        XCTAssertGreaterThanOrEqual(branch.frame.height, 44 - 0.01)
        branch.tap()
        XCTAssertTrue(branch.label.contains("展开 2"))
        XCTAssertFalse(app.buttons["thread.parent.a1"].exists)
        attach(app, "thread-collapsed-\(scheme)")
        branch.tap()
        let parent = app.buttons["thread.parent.a1"]
        reveal(parent, app: app)
        parent.tap()
        XCTAssertTrue(branch.isHittable)
        menu.tap()
        app.buttons["thread.authorOnly"].tap()
        XCTAssertTrue(app.staticTexts["thread.authorOnlyHint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thread.branch.a"].exists)
        attach(app, "thread-author-only-\(scheme)")
        app.scrollViews.firstMatch.swipeUp()
        menu.tap()
        app.buttons["thread.returnToPost"].tap()
        let focused = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "当前帖子：")).firstMatch
        XCTAssertTrue(focused.waitForExistence(timeout: 5))
        XCTAssertTrue(focused.isHittable)
        menu.tap()
        app.buttons["thread.authorOnly"].tap()
        reveal(branch, app: app)
        XCTAssertTrue(branch.label.contains("收起 2"))
    }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<7 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
