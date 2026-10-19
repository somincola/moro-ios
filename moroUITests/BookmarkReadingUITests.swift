import XCTest

final class BookmarkReadingUITests: XCTestCase {
    @MainActor func testBookmarkReadingInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testBookmarkReadingInDarkMode() { verifyFlow(scheme: "dark") }

    @MainActor private func verifyFlow(scheme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_BOOKMARK_READING", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launchEnvironment["UITEST_BOOKMARK_RESET"] = "1"
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        let first = app.buttons["bookmarks.actions.b1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        first.tap()
        app.buttons["bookmarks.toggleRead.b1"].tap()
        filter("unread", app: app)
        XCTAssertFalse(first.exists)
        XCTAssertTrue(app.buttons["bookmarks.actions.b2"].exists)
        filter("all", app: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("secret=1")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["bookmarks.actions.b2"].exists)
        attach(app, "bookmarks-search-\(scheme)")
        app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "关闭", "Cancel", "Close"])).firstMatch.tap()
        let second = app.buttons["bookmarks.actions.b2"]
        reveal(second, app: app)
        second.tap()
        app.buttons["bookmarks.remove.b2"].tap()
        XCTAssertTrue(app.staticTexts["bookmarks.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        reveal(second, app: app)
        app.cells.containing(.button, identifier: "bookmarks.actions.b2").firstMatch.swipeLeft()
        let swipeRemove = app.buttons["bookmarks.swipeRemove.b2"]
        XCTAssertTrue(swipeRemove.waitForExistence(timeout: 5), app.debugDescription)
        swipeRemove.tap()
        XCTAssertTrue(second.waitForNonExistence(timeout: 5))
        let more = app.buttons["bookmarks.loadMore"]
        reveal(more, app: app)
        more.tap()
        XCTAssertTrue(app.buttons["bookmarks.actions.b3"].waitForExistence(timeout: 5))
        XCTAssertFalse(second.exists)
        app.terminate()
        app.launchEnvironment["UITEST_BOOKMARK_RESET"] = "0"
        app.launchEnvironment["UITEST_BOOKMARK_OFFLINE"] = "1"
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.buttons["bookmarks.retry"].waitForExistence(timeout: 10))
        filter("read", app: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["bookmarks.actions.b3"].exists)
        attach(app, "bookmarks-offline-\(scheme)")
    }

    @MainActor private func filter(_ value: String, app: XCUIApplication) {
        app.buttons["bookmarks.filter"].tap()
        app.buttons["bookmarks.filter.\(value)"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 where !element.isReachable(in: app) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isReachable(in: app), app.debugDescription)
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
