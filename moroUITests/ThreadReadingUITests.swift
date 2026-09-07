import XCTest

final class ThreadReadingUITests: XCTestCase {
    @MainActor func testThreadReadingInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testThreadReadingInDarkMode() { verifyFlow(scheme: "dark") }
    @MainActor func testThreadReadingAtAccessibilityTextSize() { verifyFlow(scheme: "light", largeText: true) }
    @MainActor func testSuppliedThreadInLightMode() { verifySuppliedThread(scheme: "light") }
    @MainActor func testSuppliedThreadInDarkMode() { verifySuppliedThread(scheme: "dark") }

    @MainActor private func verifyFlow(scheme: String, largeText: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_THREAD_READING", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        }
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
        // An adjacent parent is clear from the rail; do not add another header row.
        XCTAssertFalse(app.buttons["thread.parent.a1"].exists)
        XCTAssertFalse(app.buttons["thread.branch.a1"].exists)
        menu.tap()
        app.buttons["thread.authorOnly"].tap()
        XCTAssertTrue(app.staticTexts["thread.authorOnlyHint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thread.branch.a"].exists)
        attach(app, "thread-author-only-\(scheme)")
        let parent = app.buttons["thread.parent.a1"]
        reveal(parent, app: app)
        parent.tap()
        XCTAssertTrue(branch.isHittable)
        XCTAssertFalse(app.staticTexts["thread.authorOnlyHint"].exists)
        app.scrollViews.firstMatch.swipeUp()
        menu.tap()
        app.buttons["thread.returnToPost"].tap()
        let focused = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "当前帖子：")).firstMatch
        XCTAssertTrue(focused.waitForExistence(timeout: 5))
        XCTAssertTrue(focused.isHittable)
        reveal(branch, app: app)
        XCTAssertTrue(branch.label.contains("收起 2"))
    }

    @MainActor private func verifySuppliedThread(scheme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_THREAD_READING", "UITEST_THREAD_REAL_SAMPLE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["thread.readingOptions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        attach(app, "thread-sample-original-\(scheme)")
        reveal(app.staticTexts["thread.authorContinuations"], app: app)
        attach(app, "thread-sample-additions-\(scheme)")
        let branch = app.buttons["thread.branch.117116945719580606"]
        reveal(branch, app: app)
        XCTAssertTrue(branch.label.contains("收起 7"))
        XCTAssertGreaterThanOrEqual(branch.frame.height, 44 - 0.01)
        attach(app, "thread-sample-discussion-\(scheme)")
        branch.tap()
        XCTAssertTrue(branch.label.contains("展开 7"))
        XCTAssertFalse(app.otherElements["thread.row.117116973265571189"].exists)
        attach(app, "thread-sample-collapsed-\(scheme)")
        branch.tap()
        XCTAssertTrue(app.otherElements["thread.row.117116973265571189"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thread.branch.117116973265571189"].exists)

        // This fork replies to an earlier post rather than the immediately preceding row.
        let parent = app.buttons["thread.parent.117117388752166120"]
        reveal(parent, app: app)
        attach(app, "thread-sample-reply-fork-\(scheme)")
        parent.tap()
        XCTAssertTrue(app.otherElements["thread.row.117117285240878821"].isHittable)
        menu.tap()
        app.buttons["thread.authorOnly"].tap()
        XCTAssertTrue(app.staticTexts["thread.authorOnlyHint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thread.branch.117116945719580606"].exists)
        menu.tap()
        app.buttons["thread.returnToPost"].tap()
        let focused = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "一直以为我老家村子里的老头老太们")).firstMatch
        XCTAssertTrue(focused.isHittable)
    }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<24 where !element.isHittable {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
