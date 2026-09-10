import XCTest

final class TimelineLiveUITests: XCTestCase {
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

    @MainActor private func launch(scheme: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TIMELINE_LIVE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch()
        return app
    }

    @MainActor private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
