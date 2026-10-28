import XCTest

final class ComposeEditSourceUITests: XCTestCase {
    @MainActor
    func testEditSourceLoadingFailureAndRetryInLightMode() throws {
        try verifyEditSourceFlow(colorScheme: "light")
    }

    @MainActor
    func testEditSourceLoadingFailureAndRetryInDarkMode() throws {
        try verifyEditSourceFlow(colorScheme: "dark")
    }

    @MainActor
    private func verifyEditSourceFlow(colorScheme: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_EDIT_SOURCE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = colorScheme
        app.launch(isolatedFor: self)
        defer { app.terminate() }

        let post = app.composePostButton
        XCTAssertTrue(post.waitForExistence(timeout: 8))
        XCTAssertFalse(post.isEnabled)
        XCTAssertFalse(app.textViews["compose.textInput"].exists)

        let retry = app.buttons["compose.retryEditSource"]
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        XCTAssertTrue(retry.isHittable)
        // AX frames can represent 44 pt as 43.99999999999997 after coordinate conversion.
        XCTAssertGreaterThanOrEqual(retry.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44 - 0.01)
        XCTAssertFalse(post.isEnabled)
        attachScreenshot(app, name: "edit-source-failure-\(colorScheme)")
        retry.tap()

        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let text = try XCTUnwrap(editor.value as? String)
        XCTAssertEqual(text, "原文：https://example.com/a/very/long/path?first=1&second=2\n@alice@remote.example 我用 #Swift 写了一个 App。😀")
        XCTAssertTrue(post.isEnabled)
        XCTAssertFalse(retry.exists)
        attachScreenshot(app, name: "edit-source-ready-\(colorScheme)")
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
