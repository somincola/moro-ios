import XCTest

/// iPhone Duo's inner display held landscape shows a tab's list on the left and the opened
/// thread on the right.
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
    }

    func testExploreOpensThreadsInTheSecondColumn() throws {
        let app = launch()
        defer { app.terminate() }
        app.buttons["mainTab.explore"].tap()
        let input = app.searchFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        try requireSplit(in: app)

        input.tap()
        input.typeText("Push\n")
        let result = app.tables["search.results"].cells.firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        // Open from the scope that lists posts.
        app.segmentedControls["search.scope"].buttons.element(boundBy: 1).tap()
        let post = app.tables["search.results"].staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Push target post")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 5))
        post.tap()
        assertThreadOpenedBeside(listRow: post, in: app)
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

    /// Holds the device landscape and skips unless that gives two columns.
    private func requireSplit(in app: XCUIApplication) throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let placeholder = app.staticTexts["Select a post to read the conversation here"]
        let window = app.windows.firstMatch
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in window.frame.width > window.frame.height }, object: nil)], timeout: 5)
        let width = window.frame.width
        let split = placeholder.waitForExistence(timeout: 5)
        attach(app, "split-landscape")
        try XCTSkipUnless(split,
            "Two columns need iPhone Duo unfolded and held landscape (window is \(Int(width)) pt wide)")
        attach(app, "split-empty")
    }

    /// The thread fills the right column: the placeholder goes, nothing was pushed (the list
    /// is still on screen at its place) and the thread sits right of the list.
    private func assertThreadOpenedBeside(listRow: XCUIElement, in app: XCUIApplication) {
        let placeholder = app.staticTexts["Select a post to read the conversation here"]
        XCTAssertTrue(placeholder.waitForNonExistence(timeout: 5), "The thread replaces the placeholder")
        XCTAssertTrue(listRow.isHittable, "Opening a thread must not push over the list")
        // The detail may show the row's post or its refetched copy from the fixture server.
        let listEdge = listRow.frame.maxX
        let thread = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@", "Recent activity 330", "Push target post"))
            .allElementsBoundByIndex.filter { $0.frame.minX > listEdge }
        XCTAssertFalse(thread.isEmpty, "The thread shows in the column right of the list")
        attach(app, "split-thread")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
