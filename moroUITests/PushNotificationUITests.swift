import XCTest

@MainActor
final class PushNotificationUITests: XCTestCase {
    func testNotificationQueuedBeforeShellOpensItsPost() {
        let app = launch("post")
        defer { app.terminate() }
        assertPost(in: app, session: "push-a")
        attach(app, "push-post-detail")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"),
            evaluatedWith: targetPost(in: app, session: "push-a"))
        waitForExpectations(timeout: 5)
        assertInbox(in: app)
        attach(app, "push-returned-to-inbox")
    }

    func testMissingMalformedAndRemovedAccountNotificationsOpenInbox() {
        for scenario in ["missing", "malformed", "removed-account"] {
            let app = launch(scenario)
            assertInbox(in: app)
            XCTAssertFalse(targetPost(in: app, session: "push-a").exists)
            attach(app, "push-inbox-\(scenario)")
            app.terminate()
        }
    }

    func testNotificationForAnotherAccountResolvesUsingThatAccount() {
        let app = launch("other-account")
        defer { app.terminate() }
        assertPost(in: app, session: "push-b")
        XCTAssertFalse(targetPost(in: app, session: "push-a").exists)
        attach(app, "push-other-account")
    }

    func testStatusURLResolvesToNativePost() {
        let app = launch("link")
        defer { app.terminate() }
        assertPost(in: app, session: "push-a")
    }

    func testEmptyMessagesStayVisibleAfterSwitchingSectionsAndForegrounding() {
        let app = launch("missing")
        defer { app.terminate() }
        assertInbox(in: app)
        let messages = app.buttons["Messages"]
        messages.tap()
        let empty = app.staticTexts["No conversations yet"]
        assertRemainsVisible(empty, seconds: 16)
        app.buttons["Notifications"].tap()
        messages.tap()
        assertRemainsVisible(empty, seconds: 5)

        XCUIDevice.shared.press(.home)
        app.activate()
        assertRemainsVisible(empty, seconds: 10)
        XCTAssertTrue(messages.isSelected)
        attach(app, "push-empty-messages-stable")
    }

    func testDirectMessagePushAndManualReentryStayVisibleWithoutReloadLoop() {
        let app = launch("messages")
        defer { app.terminate() }
        let body = app.descendants(matching: .any)["conversation.body.push-post"].firstMatch
        assertRemainsVisible(body, seconds: 10)
        attach(app, "push-message-detail-stable")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        let conversation = app.buttons["directMessages.conversation.push-conversation"]
        assertRemainsVisible(conversation, seconds: 10)
        app.buttons["Notifications"].tap()
        app.buttons["Messages"].tap()
        assertRemainsVisible(conversation, seconds: 5)
        conversation.tap()
        assertRemainsVisible(body, seconds: 10)
        attach(app, "push-message-manual-reentry-stable")
    }

    func testSystemNotificationTapFromBackgroundOpensPostWithoutCrashing() {
        let app = launch("system")
        defer { app.terminate() }
        let schedule = app.buttons["push.schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 10))
        schedule.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let scheduled = NSPredicate(format: "enabled == false")
        expectation(for: scheduled, evaluatedWith: schedule)
        waitForExpectations(timeout: 5)
        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Moro push routing test")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 12))
        banner.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        assertPost(in: app, session: "push-a")
        attach(app, "push-system-tap")
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PUSH_OPEN", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_PUSH_SCENARIO"] = scenario
        app.launch()
        return app
    }

    private func targetPost(in app: XCUIApplication, session: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Push target post on \(session).push-fixture.invalid")).firstMatch
    }

    private func assertPost(in app: XCUIApplication, session: String) {
        XCTAssertTrue(targetPost(in: app, session: session).waitForExistence(timeout: 12))
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].firstMatch.exists)
    }

    private func assertInbox(in app: XCUIApplication) {
        let notifications = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notifications")).firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 12))
        XCTAssertTrue(notifications.isSelected)
        XCTAssertTrue(app.buttons["mainTab.inbox"].isSelected)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertRemainsVisible(_ element: XCUIElement, seconds: TimeInterval,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 12), file: file, line: line)
        let disappears = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false OR hittable == false"), object: element)
        disappears.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [disappears], timeout: seconds), .completed,
            "Loaded message content must remain visible while the page is idle", file: file, line: line)
    }
}
