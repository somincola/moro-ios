import XCTest

@MainActor
final class SettingsHierarchyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPostingCopyAndSwitchesWithPinkTheme() {
        let app = launch(dark: true)
        defer { app.terminate() }
        tap("settings.posting", in: app)
        XCTAssertTrue(app.staticTexts["Default Post Language"].exists)
        let altText = app.switches["settings.confirm.altText"]
        XCTAssertEqual(altText.label, "Ask before posting media without alt text")
        let original = altText.value as? String
        altText.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertNotEqual(altText.value as? String, original)
        altText.tap()
        XCTAssertEqual(altText.value as? String, original)
        attach(app, "settings-posting-english-dark-pink-theme")
    }

    func testPushChangeSyncsAfterImmediatelyReturning() {
        let app = launch(pushSync: true)
        defer { app.terminate() }
        tap("settings.push", in: app)
        let mentions = app.switches["notificationSettings.push.mentions"]
        XCTAssertTrue(mentions.waitForExistence(timeout: 5))
        let original = mentions.value as? String
        let expected = ["1", "On"].contains(original ?? "") ? "off" : "on"
        mentions.tap()
        back(app)
        app.navigationBars.buttons.firstMatch.tap()
        let check = app.buttons["settings.harness.checkPush"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            check.tap()
            if app.staticTexts["settings.harness.serverMentions"].label == expected { break }
        }
        XCTAssertEqual(app.staticTexts["settings.harness.serverMentions"].label, expected)
        app.buttons["settings.sheet.open"].tap()
        tap("settings.push", in: app)
        XCTAssertNotEqual(mentions.value as? String, original)
        mentions.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notificationSettings.push.saving").firstMatch.waitForNonExistence(timeout: 8))
        back(app)
    }

    func testPushFailureKeepsChoiceAndOffersRetry() {
        let app = launch(pushSync: true, pushFailure: true)
        defer { app.terminate() }
        tap("settings.push", in: app)
        let mentions = app.switches["notificationSettings.push.mentions"]
        XCTAssertTrue(mentions.waitForExistence(timeout: 5))
        let original = mentions.value as? String
        mentions.tap()
        let changed = mentions.value as? String
        let retry = app.buttons["notificationSettings.push.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertNotEqual(original, changed)
        XCTAssertEqual(mentions.value as? String, changed)
        attach(app, "push-save-failure-preserves-choice")
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 8))
        let saving = app.descendants(matching: .any).matching(identifier: "notificationSettings.push.saving").firstMatch
        XCTAssertTrue(saving.waitForNonExistence(timeout: 8))
        XCTAssertFalse(retry.exists)
        XCTAssertEqual(mentions.value as? String, changed)
        back(app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settings.harness.checkPush"].tap()
        let expected = ["1", "On"].contains(changed ?? "") ? "on" : "off"
        let result = app.staticTexts["settings.harness.serverMentions"]
        XCTAssertTrue(NSPredicate(format: "label == %@", expected).evaluate(with: result)
            || XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: result)], timeout: 5) == .completed)
        app.buttons["settings.sheet.open"].tap()
        tap("settings.push", in: app)
        mentions.tap()
        XCTAssertTrue(saving.waitForNonExistence(timeout: 8))
    }

    func testPushFailureAfterReturningStillShowsNotice() {
        let app = launch(pushSync: true, pushFailure: true)
        defer { app.terminate() }
        tap("settings.push", in: app)
        let mentions = app.switches["notificationSettings.push.mentions"]
        XCTAssertTrue(mentions.waitForExistence(timeout: 5))
        mentions.tap()
        back(app)
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        let notice = app.descendants(matching: .any).matching(identifier: "settings.saveErrorNotice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 6))
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.isHittable)
        attach(app, "push-save-failure-after-returning")
        tap("settings.push", in: app)
        let saving = app.descendants(matching: .any).matching(identifier: "notificationSettings.push.saving").firstMatch
        XCTAssertTrue(saving.waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.buttons["notificationSettings.push.retry"].exists)
        mentions.tap()
        XCTAssertTrue(saving.waitForNonExistence(timeout: 8))
    }

    func testHomeScopesAndLocalPreferencePersistence() throws {
        let app = launch(dark: true)
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["settings.preferences"].exists)
        XCTAssertTrue(app.staticTexts["About Account"].exists)
        XCTAssertFalse(app.staticTexts["settings.currentAccount"].exists)
        attach(app, "settings-home-english-dark")
        tap("settings.display", in: app)
        tap("settings.appIcon", in: app, activate: false)
        let icon = app.buttons["settings.appIcon"]
        XCTAssertEqual(icon.label, "App Icon")
        let iconName = try XCTUnwrap(icon.value as? String)
        XCTAssertFalse(iconName.isEmpty)
        XCTAssertFalse(icon.staticTexts[iconName].exists)
        attach(app, "settings-current-app-icon-english-dark")
        tap("settings.appIcon", in: app)
        XCTAssertTrue(app.navigationBars["App Icon"].waitForExistence(timeout: 5))
        back(app)
        back(app)

        tap("settings.reading", in: app)
        XCTAssertEqual(app.switches["settings.reading.playAnimations"].label, "Emoji animations")
        let banner = app.switches["settings.reading.newPostBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        let original = banner.value as? String
        banner.tap()
        let changed = banner.value as? String
        XCTAssertNotEqual(original, changed)
        XCTAssertFalse(app.buttons["settings.postLanguage"].exists)
        attach(app, "settings-reading-english-dark")

        app.terminate()
        app.launch()
        tap("settings.reading", in: app)
        XCTAssertEqual(banner.value as? String, changed)
        banner.tap()
        XCTAssertEqual(banner.value as? String, original)
        back(app)

        tap("settings.posting", in: app)
        XCTAssertTrue(app.buttons["settings.postLanguage"].exists)
        XCTAssertTrue(app.switches["settings.confirm.altText"].exists)
        tap("settings.emoji", in: app)
        back(app)
        XCTAssertTrue(app.navigationBars["Interactions"].exists)
        attach(app, "settings-posting-english-dark")
        back(app)

        tap("settings.accounts", in: app)
        XCTAssertFalse(app.buttons["accountManagement.serverAccountSettings"].exists)
        tap("settings.logout", in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Sign-in Management"].exists)
        back(app)
        tap("settings.accountActions", in: app)
        let deletion = app.buttons["accountManagement.serverAccountSettings"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5))
        XCTAssertTrue(deletion.isHittable)
        XCTAssertEqual(deletion.label, "Delete Account")
        XCTAssertGreaterThanOrEqual(deletion.frame.height, 44)
        XCTAssertLessThanOrEqual(deletion.frame.height, 56)
        XCTAssertTrue(app.navigationBars["Delete Account"].exists)
        attach(app, "settings-delete-account-english-dark")
    }

    func testProfileDisplayAndNotificationScopesAreSeparate() {
        let app = launch()
        defer { app.terminate() }
        tap("settings.reading", in: app)
        tap("settings.profileReading", in: app)
        let local = app.switches["profile.display.featuredTags"]
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["profile.display.media"].exists)
        let original = local.value as? String
        local.tap()
        let changed = local.value as? String
        app.buttons["profile.display.save"].tap()
        tap("settings.profileReading", in: app)
        XCTAssertEqual(local.value as? String, changed)
        local.tap()
        app.buttons["profile.display.save"].tap()
        back(app)

        tap("settings.profile", in: app)
        tap("profile.edit.display", in: app)
        XCTAssertTrue(app.switches["profile.display.media"].waitForExistence(timeout: 5))
        XCTAssertTrue(["1", "On"].contains(app.switches["profile.display.media"].value as? String ?? ""))
        XCTAssertFalse(local.exists)
        XCTAssertFalse(app.buttons["profile.display.save"].isEnabled)
        attach(app, "settings-public-profile-display")
        back(app)
        back(app)

        tap("settings.push", in: app)
        XCTAssertTrue(app.navigationBars["Push Notifications"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["notificationSettings.pushPage"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["notificationSettings.intakePage"].exists)
        attach(app, "settings-device-push")
        back(app)
        tap("settings.notificationRules", in: app)
        XCTAssertTrue(app.navigationBars["Notification Rules"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["notificationSettings.intakePage"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["notificationSettings.pushPage"].exists)
        attach(app, "settings-server-notification-rules")
    }

    func testChineseDarkModeAndLargestTextKeepMenusReachable() {
        let standard = launch(chinese: true)
        XCTAssertTrue(standard.navigationBars["设置"].waitForExistence(timeout: 8))
        attach(standard, "settings-home-chinese-dark")
        standard.terminate()

        let app = launch(chinese: true, large: true)
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))
        attach(app, "settings-home-chinese-dark-large")
        tap("settings.display", in: app)
        tap("settings.appIcon", in: app, activate: false)
        XCTAssertFalse(app.buttons["settings.appIcon"].label.contains("默认"))
        attach(app, "settings-current-app-icon-chinese-dark-large")
        back(app)
        tap("settings.reading", in: app)
        let banner = app.switches["settings.reading.newPostBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(banner.frame.height, 44)
        tap("settings.profileReading", in: app)
        XCTAssertTrue(app.switches["profile.display.featuredTags"].waitForExistence(timeout: 5))
        attach(app, "settings-local-profile-chinese-dark-large")
        back(app)
        back(app)
        tap("settings.posting", in: app)
        let altText = app.switches["settings.confirm.altText"]
        XCTAssertEqual(altText.label, "发布无替代文本的媒体时询问")
        XCTAssertGreaterThan(altText.frame.height, 44)
        attach(app, "settings-posting-chinese-dark-large")
        back(app)
        tap("settings.privacy", in: app)
        XCTAssertTrue(app.navigationBars["隐私与可见性"].exists)
        XCTAssertTrue(app.switches["settings.privacy.approveFollows"].waitForExistence(timeout: 5))
        attach(app, "settings-privacy-chinese-dark-large")
        back(app)
        tap("settings.contentSafety", in: app)
        tap("settings.filters", in: app)
        back(app)
        back(app)
        XCTAssertFalse(app.staticTexts["settings.currentAccount"].exists)
        tap("settings.accountActions", in: app)
        let deletion = app.buttons["accountManagement.serverAccountSettings"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5))
        XCTAssertTrue(deletion.isHittable)
        XCTAssertGreaterThanOrEqual(deletion.frame.height, 44)
        XCTAssertGreaterThanOrEqual(deletion.frame.minX, 0)
        XCTAssertLessThanOrEqual(deletion.frame.maxX, app.windows.firstMatch.frame.maxX)
        attach(app, "settings-delete-account-chinese-dark-large")
    }

    private func launch(chinese: Bool = false, large: Bool = false, dark: Bool = false, pushSync: Bool = false, pushFailure: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SETTINGS_SHEET", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
            "-AppleLocale", chinese ? "zh_CN" : "en_US",
            "-contentLinkColor", "pink",
        ]
        app.launchEnvironment["UITEST_SETTINGS_SHEET"] = "1"
        app.launchEnvironment["UITEST_SETTINGS_ACCOUNT"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = chinese || dark ? "dark" : "light"
        if pushSync { app.launchEnvironment["UITEST_SETTINGS_PUSH_SYNC"] = "1" }
        if pushFailure { app.launchEnvironment["UITEST_PUSH_SAVE_FAILS_ONCE"] = "1" }
        if large { app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL" }
        app.launch()
        return app
    }

    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.firstMatch.tap() }

    private func tap(_ identifier: String, in app: XCUIApplication, activate: Bool = true) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        _ = element.waitForExistence(timeout: 2)
        for _ in 0..<10 where !element.exists || !element.isHittable { app.swipeUp() }
        for _ in 0..<10 where !element.exists || !element.isHittable { app.swipeDown() }
        XCTAssertTrue(element.exists, identifier)
        XCTAssertTrue(element.isHittable, identifier)
        XCTAssertGreaterThanOrEqual(element.frame.minX, 0)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.windows.firstMatch.frame.maxX)
        if activate { element.tap() }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
