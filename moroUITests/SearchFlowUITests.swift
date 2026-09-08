import XCTest

final class SearchFlowUITests: XCTestCase {
    @MainActor func testSearchFlowInLightMode() throws { try verifyFlow(colorScheme: "light") }
    @MainActor func testSearchFlowInDarkMode() throws { try verifyFlow(colorScheme: "dark") }

    @MainActor func testNativeSearchEntryHidesTabBarInLightMode() {
        verifyEntryTabBar(colorScheme: "light")
    }

    @MainActor func testNativeSearchEntryHidesTabBarInDarkMode() {
        verifyEntryTabBar(colorScheme: "dark")
    }

    @MainActor private func verifyEntryTabBar(colorScheme: String) {
        let app = launch(colorScheme: colorScheme, nativeShell: true)
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.waitForNonExistence(timeout: 3))
        let entry = app.scrollViews["search.entry"]
        XCTAssertTrue(entry.exists)
        let entryBottomWithKeyboard = entry.frame.maxY
        // The keyboard's accessibility frame can exclude its prediction bar.
        XCTAssertLessThanOrEqual(entryBottomWithKeyboard, app.keyboards.firstMatch.frame.minY)
        attach(app, "search-entry-no-tabs-\(colorScheme)")

        cancelButton(in: app).tap()
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["search.cancel"].exists)

        input.tap()
        input.typeText("Swift\n")
        XCTAssertTrue(app.tables["search.results"].cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attach(app, "search-results-tabs-restored-\(colorScheme)")

        // Clearing a submitted query also enters the same intermediate page.
        input.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["search.cancel"].waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.waitForNonExistence(timeout: 3))
        cancelButton(in: app).tap()
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        app.buttons["mainTab.home"].tap()
        XCTAssertTrue(tabBar.exists)
        app.buttons["mainTab.explore"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.exists)
    }

    @MainActor func testAccountSwitchSeparatesSearchHistory() throws {
        let app = launch(colorScheme: "light")
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        XCTAssertTrue(app.buttons["search.recent.Moro"].waitForExistence(timeout: 3))
        app.buttons["search.switchAccount"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        input.tap()
        XCTAssertTrue(app.buttons["search.recent.Other account"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["search.recent.Moro"].exists)
        assertRemovedChrome(in: app)
    }

    @MainActor func testNativeNavigationReturnsToDiscoveryAndScrolledResults() throws {
        let app = launch(colorScheme: "light", nativeShell: true)
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        let table = app.tables["search.results"]
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 10))
        let discoveryLabel = table.cells.firstMatch.label
        table.cells.firstMatch.tap()
        returnFromDetail(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(table.cells.matching(NSPredicate(format: "label == %@", discoveryLabel)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.cancel"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        input.tap()
        input.typeText("long\n")
        XCTAssertTrue(table.cells.matching(NSPredicate(format: "label CONTAINS %@", "Result long 0")).firstMatch.waitForExistence(timeout: 5))
        table.swipeUp()
        table.swipeUp()
        let target = try XCTUnwrap(table.cells.allElementsBoundByIndex.first {
            $0.isHittable && $0.label.contains("Result long")
                && $0.frame.minY > table.frame.minY + 50 && $0.frame.maxY < table.frame.maxY - 20
        })
        let label = target.label
        let originalY = target.frame.minY
        target.tap()
        returnFromDetail(in: app)
        let restored = table.cells.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertTrue(restored.isHittable)
        XCTAssertEqual(restored.frame.minY, originalY, accuracy: 3)
        XCTAssertEqual(input.value as? String, "long")
        XCTAssertFalse(app.buttons["search.cancel"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attach(app, "search-native-return-results")
    }

    @MainActor func testNativeTimelinePostsReturnToTheirDiscoveryAndResultsSources() throws {
        try verifyTimelinePosts(colorScheme: "light")
    }

    @MainActor func testNativeTimelinePostsInDarkMode() throws {
        try verifyTimelinePosts(colorScheme: "dark")
    }

    @MainActor private func verifyTimelinePosts(colorScheme: String) throws {
        let app = launch(colorScheme: colorScheme, nativeShell: true)
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        let table = app.tables["search.results"]
        let scopes = app.segmentedControls["search.scope"]
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 10))
        scopes.buttons.element(boundBy: 1).tap()
        let post = table.cells.firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 5))
        // The timeline toolbar and multi-paragraph rich text must be rendered in place.
        XCTAssertTrue(post.buttons.matching(NSPredicate(format: "label CONTAINS %@", "回复")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(post.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "结果")).firstMatch.exists)
        attach(app, "search-discovery-timeline-\(colorScheme)")
        tapFirstLine(of: post.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "结果")).firstMatch)
        returnFromDetail(in: app)
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(scopes.buttons.element(boundBy: 1).isSelected)
        XCTAssertFalse(app.buttons["search.cancel"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        input.tap()
        input.typeText("Swift\n")
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 5))
        let body = table.cells.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "结果 Swift")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        attach(app, "search-results-timeline-\(colorScheme)")
        tapFirstLine(of: body)
        returnFromDetail(in: app)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Swift")
        XCTAssertTrue(scopes.buttons.element(boundBy: 1).isSelected)
        XCTAssertFalse(app.buttons["search.cancel"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        // A toolbar action updates the row without opening detail or entering search.
        let favourite = table.cells.firstMatch.buttons.matching(NSPredicate(format: "label == %@", "喜欢")).firstMatch
        XCTAssertTrue(favourite.waitForExistence(timeout: 3), app.debugDescription)
        favourite.tap()
        let unfavourite = table.cells.firstMatch.buttons.matching(NSPredicate(format: "label CONTAINS %@", "取消喜欢")).firstMatch
        XCTAssertTrue(unfavourite.waitForExistence(timeout: 5))
        XCTAssertTrue(input.exists)
        XCTAssertFalse(app.buttons["search.cancel"].exists)
    }

    @MainActor func testSearchAtAccessibilityXXXL() throws {
        let app = launch(colorScheme: "dark", accessibilitySize: true)
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        let recent = app.buttons["search.recent.Moro"]
        XCTAssertTrue(recent.waitForExistence(timeout: 3))
        attach(app, "search-entry-accessibilityXXXL")
        recent.tap()
        let scopeMenu = app.buttons["search.scopeMenu"]
        XCTAssertTrue(scopeMenu.waitForExistence(timeout: 4))
        XCTAssertFalse(app.segmentedControls["search.scope"].exists)
        XCTAssertGreaterThanOrEqual(scopeMenu.frame.height, 44)
        assertRemovedChrome(in: app)
        attach(app, "search-results-accessibilityXXXL")
        scopeMenu.tap()
        app.buttons["嘟文"].tap()
        XCTAssertFalse(app.buttons["search.cancel"].exists)
        let posts = app.tables["search.results"]
        XCTAssertTrue(posts.cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(posts.cells.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "结果")).firstMatch.exists)
        attach(app, "search-posts-accessibilityXXXL")
    }

    @MainActor
    private func verifyFlow(colorScheme: String) throws {
        let app = launch(colorScheme: colorScheme)
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        let table = app.tables["search.results"]
        let scopes = app.segmentedControls["search.scope"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(scopes.buttons.count, 3)
        XCTAssertTrue(scopes.buttons.element(boundBy: 0).isSelected)
        assertRemovedChrome(in: app)
        let discoveryLabel = table.cells.firstMatch.label
        attach(app, "search-discovery-\(colorScheme)")
        input.tap()
        XCTAssertTrue(app.buttons["search.recent.Moro"].waitForExistence(timeout: 3))
        XCTAssertFalse(table.exists)
        XCTAssertFalse(scopes.exists)
        assertRemovedChrome(in: app)
        attach(app, "search-entry-\(colorScheme)")
        input.typeText("Swift")
        let submit = app.buttons["search.submitQuery"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        submit.tap()
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(scopes.buttons.count, 3)
        XCTAssertTrue(scopes.buttons.element(boundBy: 0).isSelected)
        assertRemovedChrome(in: app)
        attach(app, "search-results-\(colorScheme)")

        // Clear directly from results, then Cancel must abandon the submitted query.
        let clear = input.buttons.firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        XCTAssertTrue(app.buttons["search.recent.Swift"].waitForExistence(timeout: 3))
        XCTAssertFalse(table.exists)
        cancelButton(in: app).tap()
        XCTAssertTrue(table.cells.matching(NSPredicate(format: "label == %@", discoveryLabel)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(input.value as? String, "Swift")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["search.cancel"].exists)

        // Repeating the flow without clearing must also return to Discovery.
        input.tap()
        app.buttons["search.recent.Swift"].tap()
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 5))
        input.tap()
        cancelButton(in: app).tap()
        XCTAssertTrue(table.cells.matching(NSPredicate(format: "label == %@", discoveryLabel)).firstMatch.waitForExistence(timeout: 5))
        assertRemovedChrome(in: app)
    }

    @MainActor
    private func launch(colorScheme: String, accessibilitySize: Bool = false, nativeShell: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SEARCH_FLOW", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = colorScheme
        if accessibilitySize { app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL" }
        if nativeShell { app.launchEnvironment["UITEST_SEARCH_NATIVE_SHELL"] = "1" }
        app.launch()
        return app
    }

    @MainActor
    private func tapFirstLine(of body: XCUIElement) {
        // Rich text exposes one accessibility frame; its center may be a link.
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 8)).tap()
    }

    @MainActor
    private func returnFromDetail(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        back.tap()
    }

    @MainActor
    private func assertRemovedChrome(in app: XCUIApplication) {
        for identifier in ["search.save", "search.discovery", "search.manageSaved"] {
            XCTAssertFalse(app.buttons[identifier].exists)
        }
        XCTAssertFalse(app.staticTexts["已保存的搜索"].exists)
        XCTAssertFalse(app.staticTexts["Account Directory"].exists)
        XCTAssertFalse(app.staticTexts["账号目录"].exists)
    }

    @MainActor
    private func cancelButton(in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["search.cancel"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        XCTAssertTrue(button.isEnabled)
        return button
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
