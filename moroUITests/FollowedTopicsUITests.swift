import XCTest

final class FollowedTopicsUITests: XCTestCase {
    @MainActor func testTopicFollowRetryAndManagementInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testTopicFollowRetryAndManagementInDarkMode() { verifyFlow(scheme: "dark") }

    @MainActor private func verifyFlow(scheme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOPICS", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch()
        defer { app.terminate() }
        let open = app.buttons["topics.openMoro"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let follow = app.buttons["topic.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        XCTAssertTrue(follow.isEnabled)
        XCTAssertEqual(follow.label, "关注话题")
        follow.tap()
        let retry = app.buttons["topic.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(follow.label, "关注话题")
        retry.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "topic.follow").matching(NSPredicate(format: "label == %@", "取消关注话题")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "topic-followed-\(scheme)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["topics.homeMenu"].tap()
        app.buttons["topics.menu"].tap()
        let moro = app.buttons["topics.open.Moro"]
        XCTAssertTrue(moro.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["topics.loadMore"].exists)
        app.buttons["topics.loadMore"].tap()
        XCTAssertTrue(app.buttons["topics.open.Swift"].waitForExistence(timeout: 5))
        attach(app, "followed-topics-\(scheme)")
        moro.tap()
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        XCTAssertEqual(follow.label, "取消关注话题")
        follow.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "topic.follow").matching(NSPredicate(format: "label == %@", "关注话题")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["topics.open.Swift"].waitForExistence(timeout: 5))
        XCTAssertFalse(moro.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["topics.switchAccount"].tap()
        app.buttons["topics.homeMenu"].tap()
        app.buttons["topics.menu"].tap()
        XCTAssertTrue(app.buttons["topics.open.Other"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["topics.open.Swift"].exists)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
