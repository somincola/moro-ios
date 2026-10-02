import XCTest

@MainActor
final class AppStoreScreenshotUITests: XCTestCase {
    func testContentLabelsFollowAppLanguage() {
        continueAfterFailure = false
        for locale in ["zh-Hans", "en-US"] {
            let chinese = locale == "zh-Hans"
            let app = XCUIApplication()
            app.launchArguments = ["APP_STORE_SCREENSHOTS", "LOCALIZATION_AUDIT", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(\(locale))"]
            app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_COLOR_SCHEME": "light"]
            app.launch()
            XCTAssertTrue(app.buttons["home.composeButton"].waitForExistence(timeout: 20))
            let expand = app.buttons[chinese ? "展开内容" : "Show more"].firstMatch
            if !expand.isHittable { app.swipeUp() }
            XCTAssertTrue(expand.waitForExistence(timeout: 10))
            expand.tap()
            let collapse = app.buttons[chinese ? "收起内容" : "Show less"].firstMatch
            XCTAssertTrue(collapse.waitForExistence(timeout: 5))
            collapse.tap()
            let titles = chinese ? ["已被 2 条规则过滤", "媒体：1 项", "投票：2 个选项"]
                : ["Filtered by 2 rules", "Media: 1", "Poll with 2 options"]
            for title in titles {
                let label = app.staticTexts[title].firstMatch
                for _ in 0..<3 where !label.isHittable { app.swipeUp() }
                XCTAssertTrue(label.waitForExistence(timeout: 5), "\(locale): \(title)\n\(app.debugDescription)")
            }
            capture(app, locale, "localized-content")
            app.terminate()
        }
    }

    func testPostMenusFollowAppLanguage() {
        continueAfterFailure = false
        for locale in ["zh-Hans", "en-US"] {
            let chinese = locale == "zh-Hans"
            let app = XCUIApplication()
            app.launchArguments = ["APP_STORE_SCREENSHOTS", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(\(locale))"]
            app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_COLOR_SCHEME": "light"]
            app.launch()
            XCTAssertTrue(app.buttons["home.composeButton"].waitForExistence(timeout: 20))
            let more = app.buttons.matching(identifier: chinese ? "更多" : "More")
            XCTAssertTrue(more.firstMatch.waitForExistence(timeout: 10))
            for index in 0...1 {
                if index == 1 {
                    app.terminate()
                    app.launch()
                    XCTAssertTrue(app.buttons["home.composeButton"].waitForExistence(timeout: 20))
                }
                let trigger = app.buttons.matching(NSPredicate(
                    format: "identifier == %@ AND label == %@",
                    "timeline.row.\(index == 0 ? 900 : 899)", chinese ? "更多" : "More"
                )).firstMatch
                XCTAssertTrue(trigger.waitForExistence(timeout: 10))
                if !trigger.isHittable { app.swipeUp() }
                trigger.tap()
                let common = chinese
                    ? ["分享", "复制链接", "复制文字", "浏览器打开"]
                    : ["Share", "Copy Link", "Copy text", "Open in Browser"]
                let own = chinese
                    ? ["编辑帖子", "置顶到个人主页", "删除并继续编辑", "删除"]
                    : ["Edit Post", "Pin to profile", "Delete and continue editing", "Delete"]
                let other = chinese
                    ? ["隐藏 @luna", "屏蔽 @luna", "屏蔽并举报", "举报"]
                    : ["Mute @luna", "Block @luna", "Block and report", "Report"]
                for title in common + (index == 0 ? own : other) {
                    XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), "\(locale): \(title)\n\(app.debugDescription)")
                }
                capture(app, locale, index == 0 ? "menu-own" : "menu-other")
            }
            app.terminate()
        }
    }

    func testCaptureCurrentInterfaceWithOfflineContent() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_APP_STORE_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Store asset capture is opt-in.")
        }
        continueAfterFailure = false
        let locales = (ProcessInfo.processInfo.environment["SCREENSHOT_LOCALES"] ?? "en-US,zh-Hans,zh-Hant,ja,de-DE,fr-FR,it,es-ES,pt-PT,ar-SA").split(separator: ",").map(String.init)
        for locale in locales {
            let app = XCUIApplication()
            app.launchArguments = ["APP_STORE_SCREENSHOTS", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(\(locale))", "-AppleLocale", locale.replacingOccurrences(of: "-", with: "_")]
            app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_COLOR_SCHEME": "light"]
            app.launch()
            XCTAssertTrue(app.buttons["home.composeButton"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts["Alex Rivers"].firstMatch.waitForExistence(timeout: 10))
            if ProcessInfo.processInfo.environment["SCREENSHOT_COMPOSE_ONLY"] == "1" {
                captureCompose(app, locale)
                app.terminate()
                continue
            }
            capture(app, locale, "01-home")

            app.buttons["mainTab.explore"].tap()
            XCTAssertTrue(app.searchFields["search.input"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.cells.containing(NSPredicate(format: "label CONTAINS 'Luna Park'")).firstMatch.waitForExistence(timeout: 10))
            capture(app, locale, "02-explore")

            app.buttons["mainTab.inbox"].tap()
            XCTAssertTrue(app.buttons["inbox.filter.all"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Luna Park'")).firstMatch.waitForExistence(timeout: 10))
            capture(app, locale, "03-inbox")

            app.buttons["mainTab.me"].tap()
            XCTAssertTrue(app.staticTexts["Alex Rivers"].firstMatch.waitForExistence(timeout: 10))
            capture(app, locale, "04-profile")

            app.buttons["mainTab.home"].tap()
            captureCompose(app, locale)
            app.terminate()

            app.launchEnvironment["UITEST_COLOR_SCHEME"] = "dark"
            app.launch()
            XCTAssertTrue(app.buttons["home.composeButton"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts["Alex Rivers"].firstMatch.waitForExistence(timeout: 10))
            capture(app, locale, "06-dark")
            app.terminate()
        }
    }

    private func captureCompose(_ app: XCUIApplication, _ locale: String) {
        app.buttons["home.composeButton"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("A little room for good conversations.")
        let keyboardWelcome = app.buttons["Continue"]
        if keyboardWelcome.waitForExistence(timeout: 2) { keyboardWelcome.tap() }
        XCTAssertFalse(keyboardWelcome.exists, "The system keyboard welcome must not appear in store assets.")
        app.buttons["compose.emojiToggle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["compose.emojiPicker"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[":garden_1:"].waitForExistence(timeout: 10))
        capture(app, locale, "05-compose")
    }

    private func capture(_ app: XCUIApplication, _ locale: String, _ page: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "store__\(locale)__\(page)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
