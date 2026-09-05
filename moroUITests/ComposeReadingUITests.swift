import XCTest

final class ComposeReadingUITests: XCTestCase {
    @MainActor func testExpandedEditorPreviewAndMediaOrderInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testExpandedEditorPreviewAndMediaOrderInDarkMode() { verifyFlow(scheme: "dark") }

    @MainActor private func verifyFlow(scheme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_COMPOSE_READING", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch()
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let originalHeight = editor.frame.height
        editor.tap()
        editor.typeText("[A]")
        let beforeExpansion = editor.value as! String
        select("compose.expandEditor", app: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(editor.frame.height, originalHeight + 20)
        XCTAssertEqual(editor.value as? String, beforeExpansion)
        editor.typeText("[B]")
        let expanded = editor.value as! String
        XCTAssertEqual(expanded, beforeExpansion.replacingOccurrences(of: "[A]", with: "[A][B]"))
        XCTAssertTrue(expanded.contains("https://example.com/long/path?first=1&second=2"))
        attach(app, "compose-expanded-\(scheme)")
        select("compose.expandEditor", app: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, expanded)
        select("compose.preview", app: app)
        XCTAssertTrue(app.buttons["compose.previewDone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["compose.previewCW"].exists)
        XCTAssertFalse(app.buttons["compose.media.remove.reading-1"].isHittable)
        attach(app, "compose-preview-\(scheme)")
        app.buttons["compose.previewDone"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, expanded)
        select("compose.mediaOrder", app: app)
        XCTAssertTrue(app.buttons["compose.orderDone"].waitForExistence(timeout: 5))
        let rows = app.cells.containing(NSPredicate(format: "identifier BEGINSWITH %@", "compose.order."))
        XCTAssertEqual(rows.count, 3, app.debugDescription)
        let first = rows.element(boundBy: 0)
        let last = rows.element(boundBy: 2)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: last.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.9)))
        XCTAssertTrue(rows.element(boundBy: 0).descendants(matching: .any)["compose.order.reading-2"].exists)
        XCTAssertTrue(rows.element(boundBy: 2).descendants(matching: .any)["compose.order.reading-1"].exists)
        attach(app, "compose-media-order-\(scheme)")
        app.buttons["compose.orderDone"].tap()
        select("compose.mediaOrder", app: app)
        XCTAssertTrue(app.buttons["compose.orderDone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "identifier BEGINSWITH %@", "compose.order.")).element(boundBy: 0).descendants(matching: .any)["compose.order.reading-2"].exists)
    }

    @MainActor private func select(_ id: String, app: XCUIApplication) {
        app.buttons["compose.editorOptions"].tap()
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 3))
        app.buttons[id].tap()
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
