import XCTest

/// iPhone Duo's inner display held landscape keeps a tab's list full width until something
/// is opened, which then shows in a panel on the right; closing the panel brings the list
/// back to full width.
///
/// Only an unfolded iPhone Duo splits, and the simulator can't unfold it from the command
/// line (`simctl` only powers screens), so these skip in automated runs. To run them, open
/// the iPhone Duo simulator (iOS 27.1) in Xcode, unfold it, then run this class on it.
/// Other iPhones are too narrow once held landscape (iPhone 16 Pro leaves about 750 pt
/// between its safe areas), and on iPad Moro runs in iPhone compatibility mode.
@MainActor
final class ThreadSplitUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testInboxOpensThreadsInTheSecondColumn() throws {
        let app = launch()
        defer { app.terminate() }
        app.buttons["mainTab.inbox"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Recent activity 330")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        try requireSplit(in: app)

        row.tap()
        assertThreadOpenedBeside(listRow: row, in: app)

        // Closing (the panel's close button, in the system bar) restores the full-width list.
        let close = app.buttons["threadSplit.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let detail = app.descendants(matching: .any)["threadSplit.detail"]
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5), "Closing removes the panel")
        XCTAssertTrue(app.buttons["inbox.notificationSettings"].waitForExistence(timeout: 5),
            "The tab's own controls come back to the bar")
        attach(app, "split-closed")
    }

    func testExploreOpensThreadsInTheSecondColumn() throws {
        let app = launch()
        defer { app.terminate() }
        app.buttons["mainTab.explore"].tap()
        try requireSplit(in: app)
        let input = openSearchField(in: app)
        input.typeText("Push\n")
        let result = app.tables["search.results"].cells.firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        // Open from the scope that lists posts.
        app.buttons["search.bar.scope.2"].tap()
        let post = app.tables["search.results"].staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Push target post")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 5))
        post.tap()
        assertThreadOpenedBeside(listRow: post, in: app)
    }

    /// Explore also opens people and topics beside the list; what opens from there (a post
    /// on that profile) pushes inside the second column, so the list never moves.
    func testExploreOpensPeopleAndTopicsInTheSecondColumn() throws {
        let app = launch()
        defer { app.terminate() }
        app.buttons["mainTab.explore"].tap()
        try requireSplit(in: app)
        let input = openSearchField(in: app)
        input.typeText("Push\n")
        let results = app.tables["search.results"]
        let person = results.cells.firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        person.tap()
        let detail = app.descendants(matching: .any)["threadSplit.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "The profile opens in the second column")
        XCTAssertTrue(person.isHittable, "Opening a person must not push over the list")
        XCTAssertGreaterThan(detail.frame.minX, person.frame.maxX - 1)
        attach(app, "split-profile")

        app.buttons["search.bar.scope.3"].tap()
        let topic = results.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "pushtopic")).firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "pushtopic")).allElementsBoundByIndex
            .contains { $0.frame.minX > topic.frame.maxX }, "The topic replaces the profile in the second column")
        XCTAssertTrue(topic.isHittable)
        attach(app, "split-topic")
    }

    // MARK: - Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PUSH_OPEN", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_PUSH_SCENARIO"] = "inbox"
        app.launch(isolatedFor: self)
        return app
    }

    /// Holds the device landscape and skips unless that leaves room for a panel (iPhone Duo
    /// unfolded). Nothing is open yet, so there is no panel: the list is full width.
    private func requireSplit(in app: XCUIApplication) throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in window.frame.width > window.frame.height }, object: nil)], timeout: 5)
        let width = window.frame.width
        attach(app, "split-landscape")
        // The window counts its safe areas (an iPhone 16 Pro held landscape is 874 pt wide but
        // leaves about 750 pt between them), so also ask for iPhone Duo itself: only there do
        // these tab roots show the system bar.
        let isDuo = app.navigationBars.firstMatch.waitForExistence(timeout: 3)
        try XCTSkipUnless(width >= 820 && isDuo,
            "A panel needs iPhone Duo unfolded and held landscape (window is \(Int(width)) pt wide)")
        XCTAssertFalse(app.descendants(matching: .any)["threadSplit.detail"].exists,
            "No panel until something is opened")
    }

    /// On iPhone Duo Explore's field stays folded away until search is opened from the bar.
    private func openSearchField(in app: XCUIApplication) -> XCUIElement {
        let open = app.buttons["search.bar.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let input = app.searchFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        return input
    }

    /// The thread opens in the panel: nothing was pushed (the list is still on screen at its
    /// place) and the thread sits right of the list.
    private func assertThreadOpenedBeside(listRow: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(listRow.isHittable, "Opening a thread must not push over the list")
        let detail = app.descendants(matching: .any)["threadSplit.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "The thread shows in the second column")
        XCTAssertGreaterThan(detail.frame.minX, listRow.frame.maxX - 1, "…right of the list")
        attach(app, "split-thread")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
