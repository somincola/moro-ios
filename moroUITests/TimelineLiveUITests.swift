import XCTest

final class TimelineLiveUITests: XCTestCase {
    @MainActor func testCompleteUpdateDoesNotLeaveAGapAction() throws {
        let app = launch(scheme: "light", testsGaps: true)
        defer { app.terminate() }
        let count = app.staticTexts["timeline.fixture.count"]
        XCTAssertTrue(post(in: app, id: 100).waitForExistence(timeout: 10))
        XCTAssertTrue(wait { count.label == "60/0" })
        app.buttons["timeline.fixture.complete"].tap()
        XCTAssertTrue(wait { count.label == "62/0" && count.value as? String == "gaps:0;failed:0" })
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.gap.")).firstMatch.exists)
        XCTAssertTrue(post(in: app, id: 102).isHittable)
    }

    @MainActor func testGapFailurePreservesReadingPositionAndRetryResumesAutomaticLoading() throws {
        let app = launch(scheme: "light", testsGaps: true)
        defer { app.terminate() }
        let anchor = try beginReading(in: app)
        let count = app.staticTexts["timeline.fixture.count"]
        app.buttons["timeline.fixture.gapFailure"].tap()
        XCTAssertTrue(wait { (count.value as? String)?.contains("failed:1") == true })
        assertReadingPosition(anchor, in: app)

        app.buttons["timeline.newPosts"].tap()
        let retry = app.buttons["timeline.gap.100"]
        XCTAssertTrue(wait { retry.isHittable })
        retry.tap()
        XCTAssertTrue(wait { (count.value as? String)?.contains("failed:0") == true })
        for _ in 0..<10 {
            if count.value as? String == "gaps:0;failed:0" { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(wait { count.label == "68/0" && count.value as? String == "gaps:0;failed:0" })
        XCTAssertFalse(retry.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Timeline automatic gap loading"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Not only the final position: no intermediate frame may show the reading position
    /// displaced while the inserted rows wait for their offset correction.
    @MainActor func testInsertionNeverShowsAFrameWithTheReadingPositionDisplaced() throws {
        let app = launch(scheme: "light", disableAnimations: false)
        let anchor = try beginReading(in: app)
        let count = app.staticTexts["timeline.fixture.count"]
        let jump = app.staticTexts["timeline.fixture.jump"]
        for batch in 1...3 {
            app.buttons["timeline.fixture.insert"].tap()
            XCTAssertTrue(wait { count.label == "\(60 + batch * 20)/\(batch * 20)" })
            assertReadingPosition(anchor, in: app)
            XCTAssertTrue(jump.waitForExistence(timeout: 2))
            Thread.sleep(forTimeInterval: 0.5) // let the periodic label catch up
            XCTAssertEqual(jump.label, "jump:0", "Batch \(batch) showed a displaced frame")
        }
    }

    /// Returning from the background must not move the post being read, not even for a frame.
    @MainActor func testReturningFromBackgroundNeverMovesTheReadingPosition() throws {
        let app = launch(scheme: "light", disableAnimations: false)
        let anchor = try beginReading(in: app)
        let watch = app.staticTexts["timeline.fixture.watchResult"]
        app.buttons["timeline.fixture.watch"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        for round in 1...3 {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            Thread.sleep(forTimeInterval: 2)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            Thread.sleep(forTimeInterval: 1.5)
            assertReadingPosition(anchor, in: app)
        }
        XCTAssertEqual(watch.label, "watch:0", "The reading position moved on screen while returning")
    }

    /// Left at the very top, then away: on return new posts must not take over the screen.
    /// The post that was showing stays put behind the notice until the reader asks for more.
    @MainActor func testReturningAtTheTopKeepsThePostThatWasShowing() throws {
        let app = launch(scheme: "light", disableAnimations: false)
        let count = app.staticTexts["timeline.fixture.count"]
        let first = post(in: app, id: 100)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { count.label == "60/0" })
        let topY = first.frame.minY

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        Thread.sleep(forTimeInterval: 1) // let the scene settle so the tap is delivered

        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "80/20" }, "New posts are announced, not jumped to")
        XCTAssertTrue(wait { first.isHittable && abs(first.frame.minY - topY) <= 3 })
        XCTAssertFalse(post(in: app, id: 120).isHittable)

        app.buttons["timeline.newPosts"].tap()
        XCTAssertTrue(wait { count.label == "80/0" })
        XCTAssertTrue(post(in: app, id: 120).isHittable)

        // Back to live: at the top, the next batch follows the latest again.
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "100/0" })
        XCTAssertTrue(post(in: app, id: 140).isHittable)
    }

    /// Tapping the notice (full or compact) must land exactly on the latest post at the
    /// top, not a few points short of it.
    @MainActor func testTappingTheNoticeLandsExactlyOnTheLatestPost() throws {
        let app = launch(scheme: "light", disableAnimations: false)
        let count = app.staticTexts["timeline.fixture.count"]
        let first = post(in: app, id: 100)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { count.label == "60/0" })
        let topY = first.frame.minY

        _ = try beginReading(in: app)
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "80/20" })
        app.buttons["timeline.newPosts"].tap()
        let latest = post(in: app, id: 120)
        XCTAssertTrue(wait { latest.exists && abs(latest.frame.minY - topY) <= 1 },
            "Full notice: latest at y=\(latest.exists ? latest.frame.minY : -1), top is \(topY)")

        // New posts arrive while reading; reading on turns the notice compact.
        app.swipeUp(velocity: .slow)
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "100/20" })
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(wait { app.buttons["timeline.newPosts"].frame.width <= 64 })
        app.buttons["timeline.newPosts"].tap()
        let newest = post(in: app, id: 140)
        XCTAssertTrue(wait { newest.exists && abs(newest.frame.minY - topY) <= 1 },
            "Compact badge: latest at y=\(newest.exists ? newest.frame.minY : -1), top is \(topY)")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(newest.frame.minY, topY, accuracy: 1, "It must stay at the top once there")
    }

    @MainActor func testInsertionPreservesReadingPositionAndPillJumpsToLatest() throws {
        try exerciseTimeline(scheme: "light")
    }

    @MainActor func testDarkTimelineKeepsCoveredUpdatesUntilVisible() throws {
        let app = launch(scheme: "dark")
        let count = app.staticTexts["timeline.fixture.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(post(in: app, id: 100).waitForExistence(timeout: 10))
        XCTAssertTrue(wait { count.label == "60/0" })
        app.buttons["timeline.fixture.cover"].tap()
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label.hasSuffix("/20") })
        XCTAssertEqual(count.label, "60/20")
        app.buttons["timeline.fixture.cover"].tap()
        XCTAssertTrue(wait { count.label == "80/0" })
        XCTAssertTrue(post(in: app, id: 120).isHittable)
    }

    @MainActor func testAnimatedBatchesKeepReadingPositionAcrossBackground() throws {
        let app = launch(scheme: "light", disableAnimations: false)
        let anchor = try beginReading(in: app)
        let count = app.staticTexts["timeline.fixture.count"]
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "80/20" })
        assertReadingPosition(anchor, in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertEqual(count.label, "80/20")
        assertReadingPosition(anchor, in: app)

        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "100/40" })
        assertReadingPosition(anchor, in: app)
        app.buttons["timeline.newPosts"].tap()
        XCTAssertTrue(wait { count.label == "100/0" })
        XCTAssertTrue(post(in: app, id: 140).isHittable)
    }

    @MainActor func testReturningToCoveredReadingPositionAppliesEveryBatch() throws {
        let app = launch(scheme: "dark", disableAnimations: false)
        let anchor = try beginReading(in: app)
        let count = app.staticTexts["timeline.fixture.count"]
        app.buttons["timeline.fixture.cover"].tap()
        app.buttons["timeline.fixture.insert"].tap()
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "60/40" })
        app.buttons["timeline.fixture.cover"].tap()
        XCTAssertTrue(wait { count.label == "100/40" })
        assertReadingPosition(anchor, in: app)
        app.buttons["timeline.newPosts"].tap()
        XCTAssertTrue(wait { count.label == "100/0" })
        XCTAssertTrue(post(in: app, id: 140).isHittable)
    }

    @MainActor func testAnimatedUpdatesAtTopStayAtLatestWithoutUnreadCount() throws {
        let app = launch(scheme: "light", disableAnimations: false)
        let count = app.staticTexts["timeline.fixture.count"]
        XCTAssertTrue(post(in: app, id: 100).waitForExistence(timeout: 10))
        XCTAssertTrue(wait { count.label == "60/0" })
        for batch in 1...3 {
            app.buttons["timeline.fixture.insert"].tap()
            XCTAssertTrue(wait { count.label == "\(60 + batch * 20)/0" })
            XCTAssertTrue(post(in: app, id: 100 + batch * 20).isHittable)
            XCTAssertFalse(app.buttons["timeline.newPosts"].exists)
        }
    }

    @MainActor func testManualScrollToLatestClearsNoticeWithoutRefreshing() throws {
        let app = launch(scheme: "light", disableAnimations: false)
        let initialPost = post(in: app, id: 100)
        XCTAssertTrue(initialPost.waitForExistence(timeout: 10))
        let topY = initialPost.frame.minY
        let anchor = try beginReading(in: app)
        let count = app.staticTexts["timeline.fixture.count"]
        let lastRefresh = count.value as? String
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "80/20" })
        assertReadingPosition(anchor, in: app)

        let latest = post(in: app, id: 120)
        for _ in 0..<15 {
            if latest.exists && latest.isHittable { break }
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(latest.isHittable)
        let remaining = max(0, topY - latest.frame.minY)
        if remaining > 1 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: remaining)))
        }
        XCTAssertTrue(wait { count.label == "80/0" }, "Manually reaching the latest post must acknowledge the batch")
        XCTAssertFalse(app.buttons["timeline.newPosts"].exists)
        XCTAssertEqual(count.value as? String, lastRefresh, "Clearing the notice must not require a refresh request")
        app.swipeUp(velocity: .slow)
        XCTAssertEqual(count.label, "80/0")
        XCTAssertFalse(app.buttons["timeline.newPosts"].exists)
    }

    @MainActor func testContinuedReadingCompactsNoticeUntilAcknowledged() throws {
        try exerciseCompactNotice(scheme: "light")
    }

    @MainActor func testCompactNoticeRemainsReadableInDarkMode() throws {
        try exerciseCompactNotice(scheme: "dark")
    }

    @MainActor private func exerciseCompactNotice(scheme: String) throws {
        let app = launch(scheme: scheme, disableAnimations: false)
        _ = try beginReading(in: app)
        let count = app.staticTexts["timeline.fixture.count"]
        let notice = app.buttons["timeline.newPosts"]
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "80/20" })
        XCTAssertGreaterThan(notice.frame.width, 100)

        app.swipeUp(velocity: .slow)
        XCTAssertTrue(wait { notice.frame.width <= 64 })
        XCTAssertGreaterThanOrEqual(notice.frame.width, 44)
        XCTAssertGreaterThanOrEqual(notice.frame.height, 44)
        XCTAssertGreaterThan(notice.frame.minX, app.frame.midX)
        XCTAssertLessThan(notice.frame.minY, 200)
        XCTAssertEqual(count.label, "80/20")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Timeline compact notice \(scheme)"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "100/40" })
        XCTAssertLessThanOrEqual(notice.frame.width, 64, "Later batches must keep the compact presentation")
        notice.tap()
        XCTAssertTrue(wait { count.label == "100/0" })
        XCTAssertTrue(post(in: app, id: 140).isHittable)
        XCTAssertFalse(notice.exists)

        app.swipeUp(velocity: .slow)
        app.buttons["timeline.fixture.insert"].tap()
        XCTAssertTrue(wait { count.label == "120/20" })
        XCTAssertGreaterThan(notice.frame.width, 100, "A new batch starts with the full notice after acknowledgement")
    }

    @MainActor private func beginReading(in app: XCUIApplication) throws -> (label: String, y: CGFloat) {
        XCTAssertTrue(post(in: app, id: 100).waitForExistence(timeout: 10))
        XCTAssertTrue(wait { app.staticTexts["timeline.fixture.count"].label == "60/0" })
        app.swipeUp(velocity: .slow)
        let visible = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Timeline fixture ")).allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.minY > 120 && $0.frame.minY < 650 }
        let anchor = try XCTUnwrap(visible.first)
        return (anchor.label, anchor.frame.minY)
    }

    @MainActor private func assertReadingPosition(_ anchor: (label: String, y: CGFloat), in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line) {
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", anchor.label)).firstMatch
        XCTAssertTrue(wait { row.exists && abs(row.frame.minY - anchor.y) <= 3 },
            "The same post must remain at its original reading offset", file: file, line: line)
    }

    @MainActor private func exerciseTimeline(scheme: String) throws {
        let app = launch(scheme: scheme)
        XCTAssertTrue(post(in: app, id: 100).waitForExistence(timeout: 10))
        XCTAssertTrue(wait { app.staticTexts["timeline.fixture.count"].label == "60/0" })
        app.swipeUp(velocity: .slow)
        let visible = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Timeline fixture ")).allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.minY > 120 && $0.frame.minY < 650 }
        let anchor = try XCTUnwrap(visible.first)
        let label = anchor.label
        let y = anchor.frame.minY
        app.buttons["timeline.fixture.insert"].tap()
        let pill = app.buttons["timeline.newPosts"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { app.staticTexts["timeline.fixture.count"].label == "80/20" })
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch.frame.minY, y, accuracy: 3, "Inserting above a long post must preserve its reading offset")
        let start = Date()
        pill.tap()
        XCTAssertTrue(wait { self.post(in: app, id: 120).isHittable })
        XCTAssertEqual(post(in: app, id: 120).frame.minX, 72, accuracy: 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertTrue(wait { app.staticTexts["timeline.fixture.count"].label == "80/0" })
        XCTAssertFalse(pill.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Timeline live updates \(scheme)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor private func post(in app: XCUIApplication, id: Int) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Timeline fixture \(id)")).firstMatch
    }

    @MainActor private func launch(scheme: String, disableAnimations: Bool = true, testsGaps: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TIMELINE_LIVE", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            // A settings test that stops midway can leave the banner switched off on the device.
            "-timelineInAppNewPostBannerEnabled", "YES"]
        if testsGaps { app.launchArguments.append("UITEST_TIMELINE_GAPS") }
        if disableAnimations { app.launchArguments.append("UITEST_DISABLE_ANIMATIONS") }
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch(isolatedFor: self)
        return app
    }

    @MainActor private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
