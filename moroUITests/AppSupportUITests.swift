import XCTest

@MainActor
final class AppSupportUITests: XCTestCase {
    func testFeedbackOpensAnEditablePublicDraftWithKeyboard() {
        let app = launch()
        defer { app.terminate() }
        openSettings(app)
        reveal("settings.feedback", in: app).tap()
        XCTAssertTrue(app.buttons["feedback.email"].waitForExistence(timeout: 5))
        app.buttons["feedback.mastodon"].tap()
        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, "@acacius@m.somincola.org #Moro\n\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText(" feedback")
        XCTAssertTrue((editor.value as? String ?? "").contains("feedback"))
        attach(app, "mastodon-feedback-draft")
        // Deliberately stop before Publish: all tests use a fixture server.
    }

    func testCacheClearCompletesAndSettingsStillOpens() {
        let app = launch()
        defer { app.terminate() }
        openSettings(app)
        reveal("settings.storage", in: app).tap()
        let clear = app.buttons["storage.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Total cache"].exists)
        clear.tap()
        let confirmation = app.sheets["Clear Cache"].buttons["Clear Cache"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: clear)
        waitForExpectations(timeout: 10)
        attach(app, "storage-after-clear")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings.feedback"].exists)
    }

    func testProfileMoreSettingsAfterScrollingInChineseDarkLargeText() {
        let app = launch(chinese: true, dark: true, large: true)
        defer { app.terminate() }
        app.swipeUp()
        XCTAssertTrue(app.buttons["profile.moreButton"].isHittable)
        XCTAssertFalse(app.buttons["profile.settingsAvatar"].exists)
        openSettings(app)
        let feedback = reveal("settings.feedback", in: app)
        XCTAssertTrue(feedback.isHittable)
        attach(app, "settings-chinese-dark-large")
        feedback.tap()
        XCTAssertTrue(app.buttons["feedback.mastodon"].waitForExistence(timeout: 5))
        attach(app, "feedback-chinese-dark-large")
    }

    private func launch(chinese: Bool = false, dark: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PROFILE_EXPERIENCE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = dark ? "dark" : "light"
        if large { app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL" }
        app.launch()
        XCTAssertTrue(app.buttons["profile.moreButton"].waitForExistence(timeout: 12))
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertFalse(app.buttons["profile.settingsAvatar"].exists)
        app.buttons["profile.moreButton"].tap()
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        attach(app, "profile-more-settings")
        settings.tap()
        XCTAssertTrue(app.buttons["settings.storage"].waitForExistence(timeout: 8))
    }

    private func reveal(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[id]
        for _ in 0..<4 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        return element
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
