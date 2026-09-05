import XCTest

final class SearchFlowUITests: XCTestCase {
    @MainActor func testSearchFlowInLightMode() throws { try verifyFlow(colorScheme: "light") }
    @MainActor func testSearchFlowInDarkMode() throws { try verifyFlow(colorScheme: "dark") }

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
        XCTAssertFalse(app.buttons["search.save"].exists)
    }

    @MainActor func testCancelRestoresTheScrolledResultsPosition() throws {
        let app = launch(colorScheme: "light")
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("long")
        app.buttons["search.submitQuery"].tap()
        let table = app.tables["search.results"]
        XCTAssertTrue(table.cells.matching(NSPredicate(format: "label CONTAINS %@", "Result long 0")).firstMatch.waitForExistence(timeout: 5))
        table.swipeUp()
        table.swipeUp()
        let target = try XCTUnwrap(table.cells.allElementsBoundByIndex.first {
            $0.isHittable && $0.label.contains("Result long")
                && $0.frame.minY > table.frame.minY + 50 && $0.frame.maxY < table.frame.maxY - 20
        })
        let label = target.label
        let originalY = target.frame.minY
        input.tap()
        cancelButton(in: app).tap()
        let restored = table.cells.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertTrue(restored.isHittable)
        XCTAssertEqual(restored.frame.minY, originalY, accuracy: 3)
    }

    @MainActor func testSearchAtAccessibilityXXXL() throws {
        let app = launch(colorScheme: "dark", accessibilitySize: true)
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        let recent = app.buttons["search.recent.Moro"]
        XCTAssertTrue(recent.waitForExistence(timeout: 3))
        if !recent.isHittable { app.scrollViews.firstMatch.swipeUp() }
        attach(app, "search-entry-accessibilityXXXL")
        recent.tap()
        XCTAssertTrue(app.buttons["search.scopeMenu"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.segmentedControls["search.scope"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["search.save"].frame.height, 44 - 0.01)
        attach(app, "search-results-accessibilityXXXL")
    }

    @MainActor
    private func verifyFlow(colorScheme: String) throws {
        let app = launch(colorScheme: colorScheme)
        defer { app.terminate() }
        let input = app.searchFields["search.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        input.tap()
        XCTAssertTrue(app.buttons["search.recent.Moro"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tables["search.results"].exists)
        input.typeText("Swift")
        let submit = app.buttons["search.submitQuery"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["search.save"].exists)
        attach(app, "search-entry-\(colorScheme)")
        submit.tap()

        let save = app.buttons["search.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.tables["search.results"].exists)
        save.tap()
        XCTAssertFalse(save.isEnabled)
        attach(app, "search-results-\(colorScheme)")

        input.tap()
        let clear = input.buttons.firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        XCTAssertTrue(app.buttons["search.recent.Swift"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["search.saved.Swift"].exists)
        XCTAssertFalse(save.exists)
        cancelButton(in: app).tap()
        XCTAssertEqual(input.value as? String, "Swift")
        XCTAssertTrue(save.exists)

        input.tap()
        app.buttons["search.manageSaved"].tap()
        XCTAssertTrue(app.navigationBars["已保存的搜索"].waitForExistence(timeout: 5))
        app.buttons["重命名搜索"].tap()
        let name = app.textFields["搜索名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText(" notes")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Swift notes"].waitForExistence(timeout: 3))
        attach(app, "saved-searches-\(colorScheme)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.saved.Swift"].exists)
        cancelButton(in: app).tap()
        app.buttons["search.discovery"].tap()
        XCTAssertFalse(save.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.tables["search.results"].exists)
    }

    @MainActor
    private func launch(colorScheme: String, accessibilitySize: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SEARCH_FLOW", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = colorScheme
        if accessibilitySize { app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL" }
        app.launch()
        return app
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
