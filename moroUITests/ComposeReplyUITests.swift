import XCTest

final class ComposeReplyUITests: XCTestCase {
    private let completePrefix = "@alice@example.com @bob@example.com "

    @MainActor func testLocalRecipientsAppearTogether() {
        verifyImmediateReply(mode: "mentions")
    }

    @MainActor func testCachedRecipientsAppearTogether() {
        verifyImmediateReply(mode: "cached")
    }

    @MainActor func testDelayedRecipientsAppearOnceAndAreCachedOnReopen() {
        let app = launch(mode: "delayed")
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "compose.replyRecipientsLoading").firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textViews["compose.textInput"].exists)
        XCTAssertFalse(app.buttons["compose.postButton"].isEnabled)
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, completePrefix)
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["replyHarness.open"].waitForExistence(timeout: 4))
        app.buttons["replyHarness.open"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "compose.replyRecipientsLoading").firstMatch.exists)
        XCTAssertEqual(editor.value as? String, completePrefix)
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, completePrefix + "Hello")
        attach(app, name: "reply-reopened-caret")
    }

    @MainActor func testDismissWhilePreparingCanReopenWithoutPartialText() {
        let app = launch(mode: "delayed")
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "compose.replyRecipientsLoading").firstMatch.waitForExistence(timeout: 3))
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["replyHarness.open"].waitForExistence(timeout: 4))
        app.buttons["replyHarness.open"].tap()
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, completePrefix)
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, completePrefix + "Hello")
    }

    @MainActor func testFailureCanRetryAtAccessibilitySize() {
        let app = launch(mode: "retry", language: "en", dark: true, largeText: true)
        defer { app.terminate() }
        let retry = app.buttons["compose.retryReplyRecipients"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertFalse(app.textViews["compose.textInput"].exists)
        XCTAssertFalse(app.buttons["compose.postButton"].isEnabled)
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.width, 43.99)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 43.99)
        let available = app.buttons["compose.continueReplyRecipients"]
        XCTAssertTrue(available.isHittable)
        XCTAssertGreaterThanOrEqual(available.frame.height, 43.99)
        XCTAssertLessThanOrEqual(available.frame.maxX, app.frame.maxX)
        attach(app, name: "reply-failure-dark-accessibility")
        retry.tap()
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, completePrefix)
    }

    @MainActor func testFailureCanContinueWithKnownRecipients() {
        let app = launch(mode: "failure", dark: true)
        defer { app.terminate() }
        let available = app.buttons["compose.continueReplyRecipients"]
        XCTAssertTrue(available.waitForExistence(timeout: 8))
        attach(app, name: "reply-failure-chinese")
        available.tap()
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "@bob@example.com ")
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, "@bob@example.com Hello")
    }

    @MainActor func testRestoredDraftStartsReadyAndKeepsBody() {
        let app = launch(mode: "draft")
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "compose.replyRecipientsLoading").firstMatch.exists)
        XCTAssertEqual(editor.value as? String, "@bob@example.com 草稿 👋  \n")
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, "@bob@example.com 草稿 👋  \nHello")
    }

    @MainActor private func verifyImmediateReply(mode: String) {
        let app = launch(mode: mode)
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "compose.replyRecipientsLoading").firstMatch.exists)
        XCTAssertEqual(editor.value as? String, completePrefix)
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, completePrefix + "Hello")
        attach(app, name: "reply-\(mode)-ready")
    }

    @MainActor private func launch(mode: String, language: String = "zh-Hans", dark: Bool = false, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_COMPOSE_REPLY", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_REPLY_MODE"] = mode
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = dark ? "dark" : "light"
        if largeText { app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL" }
        app.launch()
        XCTAssertTrue(app.buttons["replyHarness.open"].waitForExistence(timeout: 6))
        app.buttons["replyHarness.open"].tap()
        return app
    }

    @MainActor private func focusAtEnd(_ editor: XCUIElement) {
        // XCTest's default TextView tap targets the first glyph, moving the caret inside @.
        // Tap the blank part of the editor to continue typing after the prefilled text.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7)).tap()
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
