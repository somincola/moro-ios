import XCTest

final class TimelineSwitchingUITests: XCTestCase {
    @MainActor func testHomeToLocal() throws { try exerciseSwitch(from: "home", to: "local") }
    @MainActor func testLocalToHome() throws { try exerciseSwitch(from: "local", to: "home") }
    @MainActor func testHomeToFederated() throws { try exerciseSwitch(from: "home", to: "federated") }
    @MainActor func testFederatedToHome() throws { try exerciseSwitch(from: "federated", to: "home") }
    @MainActor func testLocalToFederated() throws { try exerciseSwitch(from: "local", to: "federated") }
    @MainActor func testFederatedToLocal() throws { try exerciseSwitch(from: "federated", to: "local") }

    @MainActor private func exerciseSwitch(from: String, to: String) throws {
        let app = launch(controlSource: to)
        defer { app.terminate() }
        select(from, in: app)
        select(to, in: app)
        let base = baseID(to)
        XCTAssertTrue(post(base + 60, in: app).waitForExistence(timeout: 10))

        app.buttons["timeline.switch.add"].tap()
        pullToRefresh(in: app)
        XCTAssertTrue(wait { self.post(base + 61, in: app).isHittable }, "Refresh must present the new post after switching")
        XCTAssertFalse(app.buttons["timeline.newPosts"].exists)

        // Assert actual rows from three server pages, not only the loading spinner.
        try scrollToPost(base + 40, in: app)
        try scrollToPost(base + 20, in: app)
        try scrollToPost(base + 1, in: app)
        XCTAssertTrue(app.staticTexts["timeline.switch.requests"].label.contains("\(to):olderPages=2"))

        app.buttons["mainTab.home"].doubleTap()
        XCTAssertTrue(wait { self.post(base + 61, in: app).isHittable })
        app.buttons["timeline.switch.add"].tap()
        app.buttons["mainTab.home"].tap()
        XCTAssertTrue(wait { self.post(base + 62, in: app).isHittable }, "Retapping Home at the top must refresh the selected source")
        XCTAssertFalse(app.buttons["timeline.newPosts"].exists)

        app.buttons["mainTab.inbox"].tap()
        app.buttons["mainTab.home"].tap()
        XCTAssertEqual(app.buttons["时间线切换"].value as? String, title(to))
        XCTAssertTrue(post(base + 62, in: app).isHittable)
        app.buttons["timeline.switch.add"].tap()
        pullToRefresh(in: app)
        XCTAssertTrue(wait { self.post(base + 63, in: app).isHittable })
    }

    @MainActor func testHomeReadingPositionAndUnread() throws { try exerciseReading(source: "home") }
    @MainActor func testLocalReadingPositionAndUnread() throws { try exerciseReading(source: "local") }
    @MainActor func testFederatedReadingPositionAndUnread() throws { try exerciseReading(source: "federated") }

    @MainActor private func exerciseReading(source: String) throws {
        let app = launch(controlSource: source)
        defer { app.terminate() }
        select(source, in: app)
        app.buttons["mainTab.home"].tap()
        app.buttons["timeline.switch.add"].tap()
        app.buttons["timeline.switch.delay"].tap()
        pullToRefresh(in: app)
        scrollUp(in: app)
        revealHeader(in: app)
        let anchor = try visibleAnchor(in: app)
        app.buttons["timeline.switch.release"].tap()
        XCTAssertTrue(app.buttons["timeline.newPosts"].waitForExistence(timeout: 10))
        assertAnchor(anchor, in: app)
        select(source == "local" ? "federated" : "local", in: app)
        select(source, in: app)
        assertAnchor(anchor, in: app)
        XCTAssertTrue(app.buttons["timeline.newPosts"].exists, "Switching must not acknowledge unread posts")
        XCUIDevice.shared.press(.home)
        app.activate()
        assertAnchor(anchor, in: app)
        app.buttons["mainTab.home"].doubleTap()
        XCTAssertTrue(wait { !app.buttons["timeline.newPosts"].exists })
    }

    @MainActor func testDelayedRefreshReturnsOnlyToItsOwnTimeline() throws {
        let app = launch(controlSource: "local")
        defer { app.terminate() }
        select("local", in: app)
        app.buttons["timeline.switch.add"].tap()
        app.buttons["timeline.switch.delay"].tap()
        app.buttons["mainTab.home"].tap()
        XCTAssertTrue(wait { app.staticTexts["timeline.switch.requests"].label.contains("local:newer:started") })
        select("federated", in: app)
        XCTAssertTrue(wait { self.post(3061, in: app).isHittable })
        XCTAssertFalse(post(2061, in: app).exists)
        app.buttons["timeline.switch.release"].tap()
        XCTAssertTrue(wait { app.staticTexts["timeline.switch.requests"].label.contains("local:newer:1:2061") })
        XCTAssertTrue(post(3061, in: app).isHittable)
        select("local", in: app)
        XCTAssertTrue(wait { self.post(2061, in: app).isHittable })
        pullToRefresh(in: app)
        try scrollToPost(2040, in: app)
    }

    @MainActor func testRefreshFinishingWhileAwayPreservesTheReturningReader() throws {
        let app = launch(controlSource: "local")
        defer { app.terminate() }
        select("local", in: app)
        app.buttons["timeline.switch.add"].tap()
        app.buttons["timeline.switch.delay"].tap()
        pullToRefresh(in: app)
        scrollUp(in: app)
        revealHeader(in: app)
        let anchor = try visibleAnchor(in: app)
        select("federated", in: app)
        app.buttons["timeline.switch.release"].tap()
        XCTAssertTrue(wait { app.staticTexts["timeline.switch.requests"].label.contains("local:newer:1:2061") })
        select("local", in: app)
        assertAnchor(anchor, in: app)
        XCTAssertTrue(app.buttons["timeline.newPosts"].exists)
        app.buttons["mainTab.home"].doubleTap()
        XCTAssertTrue(wait { self.post(2061, in: app).isHittable && !app.buttons["timeline.newPosts"].exists })
    }

    @MainActor func testRefreshAndPaginationFailuresCanRetryAfterSwitching() throws {
        let app = launch(controlSource: "federated")
        defer { app.terminate() }
        select("federated", in: app)
        app.buttons["timeline.switch.add"].tap()
        app.buttons["timeline.switch.fail"].tap()
        app.buttons["mainTab.home"].tap()
        XCTAssertTrue(wait { app.staticTexts["timeline.switch.requests"].label.contains("federated:newer:failed") })
        app.buttons["timeline.switch.release"].tap()
        app.buttons["mainTab.home"].tap()
        XCTAssertTrue(wait { self.post(3061, in: app).isHittable })
        app.buttons["timeline.switch.fail"].tap()
        let retry = app.buttons["timeline.pagination.retry"]
        for _ in 0..<20 {
            if retry.exists && retry.isHittable { break }
            scrollUp(in: app)
        }
        XCTAssertTrue(retry.isHittable)
        app.buttons["timeline.switch.release"].tap()
        retry.tap()
        try scrollToPost(3040, in: app)
        XCTAssertFalse(retry.exists)
    }

    @MainActor func testRepeatedSwitchesKeepTheFinalPageInteractive() throws {
        let app = launch()
        defer { app.terminate() }
        for index in 0..<18 { select(["local", "federated", "home"][index % 3], in: app) }
        app.buttons["timeline.switch.add"].tap()
        pullToRefresh(in: app)
        XCTAssertTrue(wait { self.post(1061, in: app).isHittable })
        try scrollToPost(1040, in: app)
        app.buttons["mainTab.home"].doubleTap()
        XCTAssertTrue(wait { self.post(1061, in: app).isHittable })
    }

    @MainActor private func launch(controlSource: String = "home") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TIMELINE_LIVE", "UITEST_TIMELINE_SWITCHING",
            "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            // A settings test that stops midway can leave the banner switched off on the device.
            "-timelineInAppNewPostBannerEnabled", "YES"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITEST_TIMELINE_CONTROL_SOURCE"] = controlSource
        app.launch(isolatedFor: self)
        XCTAssertTrue(post(1060, in: app).waitForExistence(timeout: 15))
        return app
    }

    private func baseID(_ source: String) -> Int { source == "home" ? 1000 : (source == "local" ? 2000 : 3000) }
    private func title(_ source: String) -> String { source == "home" ? "关注" : (source == "local" ? "本站" : "跨站") }

    @MainActor private func select(_ source: String, in app: XCUIApplication) {
        let menu = app.buttons["时间线切换"]
        if menu.value as? String == title(source) { return }
        if !menu.isHittable { revealHeader(in: app) }
        XCTAssertTrue(wait { menu.isHittable })
        menu.tap()
        app.buttons[title(source)].tap()
        XCTAssertTrue(wait { menu.value as? String == self.title(source) })
    }

    @MainActor private func post(_ id: Int, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Switch ", String(id))).firstMatch
    }

    @MainActor private func pullToRefresh(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
    }

    @MainActor private func scrollUp(in app: XCUIApplication) {
        app.swipeUp(velocity: .slow)
    }

    @MainActor private func revealHeader(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 65)))
    }

    @MainActor private func scrollToPost(_ id: Int, in app: XCUIApplication) throws {
        for _ in 0..<35 {
            let row = post(id, in: app)
            if row.exists && row.isHittable { return }
            scrollUp(in: app)
        }
        XCTAssertTrue(post(id, in: app).isHittable, "Expected appended post \(id)")
    }

    @MainActor private func visibleAnchor(in app: XCUIApplication) throws -> (String, CGFloat) {
        let candidates = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Switch "))
            .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY > 150 && $0.frame.minY < 470 }
        let row = try XCTUnwrap(candidates.first)
        return (row.label, row.frame.minY)
    }

    @MainActor private func assertAnchor(_ anchor: (String, CGFloat), in app: XCUIApplication) {
        let row = app.staticTexts[anchor.0]
        XCTAssertTrue(wait { row.exists && abs(row.frame.minY - anchor.1) <= 3 },
            "Reading position must survive the transition: expected y=\(anchor.1), actual y=\(row.exists ? row.frame.minY : -1)")
    }

    @MainActor private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 10) == .completed
    }
}
