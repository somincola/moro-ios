import XCTest

@MainActor
final class PushNotificationUITests: XCTestCase {
    func testNotificationQueuedBeforeShellOpensItsPost() {
        let app = launch("post")
        defer { app.terminate() }
        assertPost(in: app, session: "push-a")
        attach(app, "push-post-detail")
        backButton(in: app).tap()
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

    func testInboxTabsAndNotificationSettingsStayUsableAfterSwitchingAndForegrounding() {
        let app = launch("inbox")
        defer { app.terminate() }
        app.buttons["mainTab.inbox"].tap()
        assertInbox(in: app)
        XCTAssertFalse(app.buttons["Messages"].exists)
        let all = app.buttons["inbox.filter.all"]
        let mentions = app.buttons["inbox.filter.mentions"]
        let settings = app.buttons["inbox.notificationSettings"]
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.buttons["inbox.filter.menu"].exists)
        XCTAssertTrue(all.isSelected)

        mentions.tap()
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text("Private reply", in: app).exists)
        XCTAssertTrue(mentions.isSelected)
        all.tap()
        mentions.tap()
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(mentions.isSelected)
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5))
        attach(app, "inbox-mentions-with-private-posts")
        all.tap()
        assertInbox(in: app)
        XCTAssertTrue(text("Recent activity 330", in: app).waitForExistence(timeout: 5))

        settings.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        attach(app, "inbox-notification-settings")
    }

    func testInboxPaginatesAndRefreshesAfterChangingTabs() {
        let app = launch("inbox")
        defer { app.terminate() }
        app.buttons["mainTab.inbox"].tap()
        assertInbox(in: app)
        let scrollView = app.scrollViews.firstMatch
        let oldest = text("Favourite page item 180", in: app)
        for _ in 0..<18 {
            if oldest.exists && oldest.isHittable { break }
            scrollView.swipeUp()
        }
        XCTAssertTrue(oldest.isHittable, "The second page of All should load")
        attach(app, "inbox-all-second-page")

        app.buttons["inbox.filter.mentions"].tap()
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5))
        app.buttons["inbox.filter.all"].tap()
        XCTAssertTrue(text("Recent activity 330", in: app).waitForExistence(timeout: 5))
        let dragStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let dragEnd = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertTrue(text("New activity 331", in: app).waitForExistence(timeout: 5))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertTrue(text("New activity 332", in: app).waitForExistence(timeout: 5),
            "Pull to refresh must request and insert another notification after switching tabs")
        XCTAssertTrue(app.buttons["inbox.filter.all"].isSelected)
        attach(app, "inbox-all-refreshed")
    }

    func testInboxSurvivesCacheClearAndOfflineRestartThenAutomaticallyRefreshes() {
        let app = launch("inbox", environment: ["UITEST_SNAPSHOT_CONTROLS": "1"])
        defer { app.terminate() }
        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(text("Recent activity 330", in: app).waitForExistence(timeout: 5))
        app.buttons["inbox.filter.mentions"].tap()
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5))
        app.buttons["inbox.testClearCache"].tap()
        XCTAssertTrue(app.buttons["Cache cleared"].waitForExistence(timeout: 5))
        app.terminate()

        app.launchEnvironment["UITEST_PRESERVE_NOTIFICATION_SNAPSHOT"] = "1"
        app.launchEnvironment["UITEST_NOTIFICATIONS_OFFLINE"] = "1"
        app.launch()
        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(text("Recent activity 330", in: app).waitForExistence(timeout: 5),
            "A cold offline launch must restore notification content after clearing disposable caches")
        XCTAssertTrue(app.descendants(matching: .any)["notifications.refreshRetry"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["inbox.filter.mentions"].tap()
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5))
        attach(app, "inbox-offline-reading-snapshot")
        app.terminate()

        app.launchEnvironment.removeValue(forKey: "UITEST_NOTIFICATIONS_OFFLINE")
        app.launchEnvironment["UITEST_NOTIFICATIONS_UPDATED"] = "1"
        app.launch()
        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(text("New activity after restart", in: app).waitForExistence(timeout: 5),
            "Restoring a snapshot must also trigger one automatic network refresh")
        XCTAssertTrue(text("Recent activity 330", in: app).exists)
        attach(app, "inbox-restored-and-refreshed")
    }

    func testGroupedNotificationsContinuePagingWithoutAnotherScrollAppearance() {
        let app = launch("inbox", environment: ["UITEST_NOTIFICATIONS_GROUPED": "1"])
        defer { app.terminate() }
        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(text("Recent activity 330", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5),
            "A first page consolidated to one row must automatically load the still-visible next page")
        attach(app, "inbox-grouped-page-continues")
    }

    func testDirectMessagePushReturnsToMentionsWithoutMessagesEntry() {
        let app = launch("messages")
        defer { app.terminate() }
        let body = app.descendants(matching: .any)["conversation.body.push-post"].firstMatch
        assertRemainsVisible(body, seconds: 3)
        attach(app, "push-message-detail-stable")
        backButton(in: app).tap()
        let mentions = app.buttons["inbox.filter.mentions"]
        XCTAssertTrue(mentions.waitForExistence(timeout: 5))
        XCTAssertTrue(mentions.isSelected)
        XCTAssertFalse(app.buttons["Messages"].exists)
        XCTAssertTrue(text("Push target post on push-a.push-fixture.invalid", in: app)
            .waitForExistence(timeout: 5))
        attach(app, "push-message-returned-to-mentions")
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

    private func launch(_ scenario: String, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PUSH_OPEN", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_PUSH_SCENARIO"] = scenario
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        return app
    }

    /// The system back button no longer carries the "BackButton" identifier; match its label too.
    private func backButton(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")).firstMatch
    }

    private func targetPost(in app: XCUIApplication, session: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Push target post on \(session).push-fixture.invalid")).firstMatch
    }

    private func assertPost(in app: XCUIApplication, session: String) {
        XCTAssertTrue(targetPost(in: app, session: session).waitForExistence(timeout: 12))
        XCTAssertTrue(backButton(in: app).exists)
    }

    private func assertInbox(in app: XCUIApplication) {
        let notifications = app.buttons["inbox.filter.all"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 12))
        XCTAssertTrue(notifications.isSelected)
        XCTAssertTrue(app.buttons["mainTab.inbox"].isSelected)
    }

    private func text(_ value: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
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
