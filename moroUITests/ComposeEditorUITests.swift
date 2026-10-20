import XCTest

final class ComposeEditorUITests: XCTestCase {
    @MainActor func testNewPostAutofocusAndCompletions() {
        verifyCompletions(mode: "new", prefix: "", dark: false)
    }

    @MainActor func testReplyAutofocusAndCompletionsInDarkMode() {
        verifyCompletions(mode: "mentions", prefix: "@alice@example.com @bob@example.com ", dark: true)
    }

    @MainActor func testHashtagSuggestionsShowRecentUsageAndHandleMissingHistory() {
        let app = launch(mode: "new")
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("#Mov")
        let movies = app.buttons["compose.suggestion.hashtag.movies"]
        XCTAssertTrue(movies.waitForExistence(timeout: 5))
        let activity = movies.staticTexts["compose.suggestion.activity.movies"]
        XCTAssertEqual(activity.label, "近期使用 51 次")
        XCTAssertFalse(app.staticTexts["compose.suggestion.activity.movienight"].exists)
        XCTAssertTrue(app.buttons["compose.suggestion.hashtag.movienight"].isHittable)
        attach(app, name: "composer-hashtag-usage")

        app.scrollViews["compose.suggestions"].swipeUp()
        let lastTag = app.buttons["compose.suggestion.hashtag.moviechat"]
        XCTAssertTrue(lastTag.isHittable)
        lastTag.tap()
        XCTAssertEqual(editor.value as? String, "#MovieChat ")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    @MainActor private func verifyCompletions(mode: String, prefix: String, dark: Bool) {
        let app = launch(mode: mode, dark: dark)
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // No tap on the editor: opening must put the caret after any reply prefill.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "composer-\(mode)-autofocus")
        editor.typeText("Hello @han")
        let account = app.buttons["compose.suggestion.account.hanna"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        XCTAssertLessThan(account.frame.maxY, app.keyboards.firstMatch.frame.minY)
        attach(app, name: "composer-\(mode)-mentions")
        account.tap()
        XCTAssertEqual(editor.value as? String, prefix + "Hello @hanna@remote.example ")
        XCTAssertTrue(account.waitForNonExistence(timeout: 3))
        editor.typeText("#Sw")
        let hashtag = app.buttons["compose.suggestion.hashtag.swiftui"]
        XCTAssertTrue(hashtag.waitForExistence(timeout: 5))
        attach(app, name: "composer-\(mode)-hashtags")
        hashtag.tap()
        editor.typeText("done")
        XCTAssertEqual(editor.value as? String, prefix + "Hello @hanna@remote.example #SwiftUI done")
        XCTAssertFalse(hashtag.exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["compose.postButton"].isEnabled)
        attach(app, name: "composer-\(mode)-completed-tokens")
    }

    @MainActor func testManualMentionsAndHashtagsKeepFollowingTextEditable() {
        let app = launch(mode: "new")
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("@hanna@remote.example #SwiftUI normal text\n#中文话题 继续写正文")
        XCTAssertEqual(editor.value as? String, "@hanna@remote.example #SwiftUI normal text\n#中文话题 继续写正文")
        XCTAssertFalse(app.otherElements["compose.suggestions"].exists)
        attach(app, name: "composer-manual-token-colors")
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "内容")
        XCTAssertTrue((editor.value as? String)?.hasSuffix("继续写内容") == true)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    @MainActor func testLongPostScrollsWithPageAndKeepsTypingVisible() {
        let app = launch(mode: "long")
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["compose.contentScroll"]
        XCTAssertFalse(app.buttons["compose.audienceMenu"].isHittable)
        editor.typeText("Last line")
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\nLast line") == true)
        let keyboardTop = app.keyboards.firstMatch.frame.minY
        let toolbar = app.buttons["compose.mediaMenu"]
        XCTAssertLessThanOrEqual(toolbar.frame.maxY, keyboardTop + 1)
        // The whole growing editor's bottom follows the caret into the visible page.
        XCTAssertLessThanOrEqual(editor.frame.maxY, toolbar.frame.minY + 15)
        attach(app, name: "composer-long-caret")
        for _ in 0..<6 where !app.buttons["compose.audienceMenu"].isHittable {
            scroll.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(app.buttons["compose.audienceMenu"].isHittable)
        attach(app, name: "composer-long-scrolled-to-header")
    }

    @MainActor func testCompletionInMiddleKeepsFollowingBodyAndClosesSuggestions() {
        let app = launch(mode: "new")
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("@Han\nlater text")
        // Use UIKit's caret-placement gesture on the first line. A short tap can
        // select a word for spell checking instead of collapsing the selection.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.07)).press(forDuration: 0.6)
        let account = app.buttons["compose.suggestion.account.hanna"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertEqual(editor.value as? String, "@hanna@remote.example\nlater text")
        XCTAssertTrue(account.waitForNonExistence(timeout: 3))
        editor.typeText("!")
        XCTAssertEqual(editor.value as? String, "@hanna@remote.example!\nlater text")
    }

    @MainActor func testLargeTextSuggestionsAndToolbarRemainUsable() {
        let app = launch(mode: "new", dark: true, largeText: true)
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("@han")
        let account = app.buttons["compose.suggestion.account.hanna"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        XCTAssertTrue(account.isHittable)
        XCTAssertLessThan(account.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let handle = account.staticTexts["@hanna@remote.example"]
        XCTAssertTrue(handle.exists)
        XCTAssertLessThanOrEqual(handle.frame.maxY, app.buttons["compose.mediaMenu"].frame.minY)
        attach(app, name: "composer-accessibility-suggestions")
        account.tap()
        editor.typeText("Hello")
        XCTAssertEqual(editor.value as? String, "@hanna@remote.example Hello")
        XCTAssertTrue(app.buttons["compose.mediaMenu"].isHittable)
    }

    @MainActor func testEmojiKeyboardPreservesCaretAndDoesNotDismissEditor() {
        let app = launch(mode: "new")
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("first second")
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.06)).tap()
        let toggle = app.buttons["compose.emojiToggle"]
        toggle.tap()
        let picker = app.descendants(matching: .any)["compose.emojiPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        editor.typeText("X")
        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.contains("X"))
        XCTAssertFalse(text.hasSuffix("X"))
        XCTAssertTrue(text.replacingOccurrences(of: "X", with: "") == "first second")
    }

    @MainActor private func launch(mode: String, dark: Bool = false, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_COMPOSE_REPLY", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_REPLY_MODE": mode,
                                 "UITEST_COLOR_SCHEME": dark ? "dark" : "light"]
        if largeText {
            app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.buttons["replyHarness.open"].waitForExistence(timeout: 6))
        app.buttons["replyHarness.open"].tap()
        return app
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
