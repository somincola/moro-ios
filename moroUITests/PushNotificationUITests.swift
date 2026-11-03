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
        app.launch(isolatedFor: self)
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
        app.launch(isolatedFor: self)
        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(text("New activity after restart", in: app).waitForExistence(timeout: 5),
            "Restoring a snapshot must also trigger one automatic network refresh")
        XCTAssertTrue(text("Recent activity 330", in: app).exists)
        attach(app, "inbox-restored-and-refreshed")
    }

    func testReTappingInboxAtTheTopStartsThePullToRefresh() {
        let app = launch("inbox", environment: ["UITEST_NOTIFICATIONS_DELAY": "4"])
        defer { app.terminate() }
        let inboxTab = app.buttons["mainTab.inbox"]
        inboxTab.tap()
        XCTAssertTrue(text("Recent activity 330", in: app).waitForExistence(timeout: 10))
        let pullRefresh = pullRefreshRunning(in: app)
        XCTAssertFalse(pullRefresh.exists)

        inboxTab.tap()
        XCTAssertTrue(pullRefresh.waitForExistence(timeout: 3),
            "Re-tapping Inbox at the top must start the list's own pull to refresh (spinner, rows pushed down)")
        attach(app, "inbox-retap-pull-spinner")
        let newest = text("New activity 331", in: app)
        XCTAssertTrue(newest.waitForExistence(timeout: 8))
        XCTAssertTrue(pullRefresh.waitForNonExistence(timeout: 5), "The spinner ends with the refresh")
        XCTAssertTrue(waitUntil(timeout: 3) { newest.isHittable },
            "A refresh the reader asked for shows the new notification at the top, not above the screen")
        XCTAssertFalse(app.buttons["notifications.newNotifications"].exists)
    }

    func testOpeningInboxWithABadgeShowsTheSpinnerOnlyWhenTheRequestIsSlow() {
        let app = launch("inbox", environment: [
            "UITEST_NOTIFICATIONS_UNREAD": "3", "UITEST_NOTIFICATIONS_DELAY": "4",
        ])
        defer { app.terminate() }
        inboxTabAndWait(in: app, for: "Recent activity 330")
        let pullRefresh = pullRefreshRunning(in: app)
        XCTAssertTrue(pullRefresh.waitForNonExistence(timeout: 5))
        leaveInboxAndComeBackWithABadge(in: app)

        // Coming back with a badge refreshes at once; resting at the top while it is slow,
        // the spinner shows late and ends with the request.
        XCTAssertTrue(pullRefresh.waitForExistence(timeout: 3),
            "A slow refresh opened over unread notifications shows the spinner while the reader rests at the top")
        attach(app, "inbox-badge-late-spinner")
        let newest = text("New activity 331", in: app)
        XCTAssertTrue(newest.waitForExistence(timeout: 8))
        XCTAssertTrue(pullRefresh.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 3) { newest.isHittable })
    }

    func testNewNotificationsWhileReadingOlderOnesWaitBehindThePill() {
        let app = launch("inbox", environment: ["UITEST_NOTIFICATIONS_UNREAD": "3"])
        defer { app.terminate() }
        inboxTabAndWait(in: app, for: "Recent activity 330")
        let scrollView = app.scrollViews.firstMatch
        scrollView.swipeUp()
        let reading = text("Recent activity 320", in: app)
        XCTAssertTrue(waitUntil(timeout: 3) { reading.exists && reading.isHittable })
        let readingFrame = reading.frame

        // Back with a badge: the refresh brings a new notification, but the reader is further
        // down, so the rows they are reading stay put and a pill appears.
        leaveInboxAndComeBackWithABadge(in: app)
        let pill = app.buttons["notifications.newNotifications"]
        XCTAssertTrue(pill.waitForExistence(timeout: 8),
            "New notifications above the reader are announced, not scrolled into view")
        XCTAssertTrue(pill.label.contains("1 new notifications"), "Got: \(pill.label)")
        XCTAssertTrue(reading.isHittable)
        XCTAssertEqual(reading.frame.minY, readingFrame.minY, accuracy: 2,
            "The row being read must not move when new notifications arrive above it")
        XCTAssertFalse(text("New activity 331", in: app).isHittable)
        attach(app, "inbox-new-notifications-pill")

        pill.tap()
        XCTAssertTrue(waitUntil(timeout: 3) { self.text("New activity 331", in: app).isHittable },
            "The pill scrolls to the new notification")
        XCTAssertTrue(pill.waitForNonExistence(timeout: 3), "The pill goes once the new rows are seen")
    }

    func testOpeningInboxOverSavedNotificationsRefreshesQuietly() {
        let app = launch("inbox")
        inboxTabAndWait(in: app, for: "Recent activity 330")
        // Rows show before the snapshot is written; loading another filter lets it finish.
        app.buttons["inbox.filter.mentions"].tap()
        XCTAssertTrue(text("Private initial mention", in: app).waitForExistence(timeout: 5))
        app.buttons["inbox.filter.all"].tap()
        app.terminate()

        app.launchEnvironment["UITEST_PRESERVE_NOTIFICATION_SNAPSHOT"] = "1"
        app.launchEnvironment["UITEST_NOTIFICATIONS_UPDATED"] = "1"
        app.launchEnvironment["UITEST_NOTIFICATIONS_DELAY"] = "4"
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(text("Recent activity 330", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(pullRefreshRunning(in: app).waitForExistence(timeout: 2),
            "An automatic refresh must not start the pull spinner")
        XCTAssertFalse(app.staticTexts["Refreshing..."].exists)
        XCTAssertTrue(text("New activity after restart", in: app).waitForExistence(timeout: 8),
            "The automatic refresh still runs")
    }

    func testReTappingInboxAwayFromTheTopOnlyScrollsBack() {
        let app = launch("inbox")
        defer { app.terminate() }
        inboxTabAndWait(in: app, for: "Recent activity 330")
        let newest = text("Recent activity 330", in: app)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(waitUntil(timeout: 3) { !newest.isHittable })

        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(waitUntil(timeout: 3) { newest.isHittable }, "Re-tapping away from the top scrolls back up")
        XCTAssertFalse(text("New activity 331", in: app).waitForExistence(timeout: 2),
            "Scrolling back up must not also refresh")
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
        app.launch(isolatedFor: self)
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

    /// Seeing the newest rows clears the badge. The fixture's server keeps reporting unread
    /// notifications, so foregrounding (which asks it again) brings the badge back.
    private func leaveInboxAndComeBackWithABadge(in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line) {
        let inbox = app.buttons["mainTab.inbox"]
        func showsBadge() -> Bool { inbox.label.contains("unread") }
        XCTAssertTrue(waitUntil(timeout: 5) { !showsBadge() },
            "Rows on screen count as seen and clear the badge", file: file, line: line)
        app.buttons["mainTab.home"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(waitUntil(timeout: 8) { showsBadge() },
            "Foregrounding restores the server's unread count", file: file, line: line)
        inbox.tap()
    }

    private func pullRefreshRunning(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["notifications.pullRefreshRunning"].firstMatch
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func inboxTabAndWait(in app: XCUIApplication, for value: String) {
        app.buttons["mainTab.inbox"].tap()
        XCTAssertTrue(text(value, in: app).waitForExistence(timeout: 10))
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
