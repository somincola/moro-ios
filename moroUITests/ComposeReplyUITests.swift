import XCTest

final class ComposeReplyUITests: XCTestCase {
    private let completePrefix = "@alice@example.com @bob@example.com "

    @MainActor func testOriginalReplyMentionsOnlyItsAuthor() {
        verifyImmediateReply(mode: "original", prefix: "@alice@example.com ")
    }

    @MainActor func testLocalRecipientsAppearTogether() {
        verifyImmediateReply(mode: "mentions", prefix: completePrefix)
    }

    @MainActor func testCachedRecipientsAppearTogether() {
        verifyImmediateReply(mode: "cached", prefix: completePrefix)
    }

    @MainActor func testMissingAccountAllowsImmediateEditingWithoutRequests() {
        let app = launch(mode: "missing", language: "en", dark: true, largeText: true)
        defer { app.terminate() }
        let editor = readyEditor(in: app, prefix: "@bob@example.com ")
        XCTAssertTrue(app.buttons["compose.postButton"].isEnabled)
        attach(app, name: "reply-offline-dark-accessibility")
        app.navigationBars.buttons["Cancel"].tap()
        assertNoRecipientRequests(in: app)

        app.buttons["replyHarness.open"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, "@bob@example.com Hello")
    }

    @MainActor func testDismissAndReopenKeepsPrefixWithoutRequests() {
        let app = launch(mode: "cached")
        defer { app.terminate() }
        _ = readyEditor(in: app, prefix: completePrefix)
        app.navigationBars.buttons["取消"].tap()
        assertNoRecipientRequests(in: app)
        app.buttons["replyHarness.open"].tap()
        let editor = readyEditor(in: app, prefix: completePrefix)
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, completePrefix + "Hello")
    }

    @MainActor func testClearingPrefillDoesNotAddItBack() {
        let app = launch(mode: "mentions")
        defer { app.terminate() }
        let editor = readyEditor(in: app, prefix: completePrefix)
        focusAtEnd(editor)
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: completePrefix.count))
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, "Hello")
    }

    @MainActor func testRestoredDraftKeepsBodyAndCaret() {
        let app = launch(mode: "draft")
        defer { app.terminate() }
        let prefix = "@bob@example.com 草稿 👋  \n"
        let editor = readyEditor(in: app, prefix: prefix)
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, prefix + "Hello")
    }

    @MainActor private func verifyImmediateReply(mode: String, prefix: String) {
        let app = launch(mode: mode)
        defer { app.terminate() }
        let editor = readyEditor(in: app, prefix: prefix)
        XCTAssertTrue(app.buttons["compose.postButton"].isEnabled)
        focusAtEnd(editor)
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, prefix + "Hello")
        attach(app, name: "reply-\(mode)-ready")
    }

    @MainActor private func readyEditor(in app: XCUIApplication, prefix: String) -> XCUIElement {
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "compose.replyRecipientsLoading").firstMatch.exists)
        XCTAssertFalse(app.buttons["compose.retryReplyRecipients"].exists)
        XCTAssertEqual(editor.value as? String, prefix)
        return editor
    }

    @MainActor private func assertNoRecipientRequests(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["replyHarness.open"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["replyHarness.recipientRequests"].label, "Recipient requests: 0")
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
