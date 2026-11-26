import XCTest

@MainActor
final class StatusEngagementUITests: XCTestCase {
    private let sourceNote = "名单来自你当前的服务器。其他服务器的帖子可能只显示部分互动账号。"

    func testSwitchListsOpenProfileAndReturnToPost() {
        let app = launch("both")
        defer { app.terminate() }
        let entry = app.buttons["statusDetail.viewEngagement"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertEqual(entry.label, "查看互动")
        let originalY = entry.frame.midY
        capture(app, "01-detail")
        entry.tap()

        let likes = app.buttons["engagement.tab.favourites"]
        let boosts = app.buttons["engagement.tab.boosts"]
        let liked = app.buttons["profile.connection.yuki"]
        XCTAssertTrue(liked.waitForExistence(timeout: 5))
        XCTAssertEqual(likes.label, "喜欢 5")
        XCTAssertEqual(boosts.label, "转发 2")
        XCTAssertEqual(likes.frame.width, boosts.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(likes.frame.height, 44)
        XCTAssertTrue(likes.isSelected)
        XCTAssertFalse(boosts.isSelected)
        capture(app, "02-favourites")
        let lastAccount = app.buttons["profile.connection.mira"]
        for _ in 0..<3 where !lastAccount.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(lastAccount.isHittable)
        boosts.tap()
        let boosted = app.buttons["profile.connection.sora"]
        XCTAssertTrue(boosted.waitForExistence(timeout: 5))
        XCTAssertTrue(boosts.isSelected)
        XCTAssertFalse(liked.exists)
        capture(app, "03-boosts")
        boosted.tap()
        XCTAssertTrue(app.buttons["profile.stat.followers"].waitForExistence(timeout: 8))
        capture(app, "04-profile")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(boosted.waitForExistence(timeout: 5))
        XCTAssertTrue(boosts.isSelected)
        likes.tap()
        XCTAssertTrue(liked.waitForExistence(timeout: 5))
        app.buttons["engagement.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.frame.midY, originalY, accuracy: 2)
    }

    func testReturningFromProfileKeepsScrolledAccountPosition() {
        let app = launch("long")
        defer { app.terminate() }
        let entry = app.buttons["statusDetail.viewEngagement"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let first = app.buttons["profile.connection.yuki"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let target = app.buttons["profile.connection.fern-12"]
        for _ in 0..<10 where !target.isHittable {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(target.isHittable)
        let originalY = target.frame.midY
        target.tap()
        XCTAssertTrue(app.buttons["profile.stat.followers"].waitForExistence(timeout: 8))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.isHittable)
        XCTAssertEqual(target.frame.midY, originalY, accuracy: 6)
    }

    func testOnlyBoostsOpensBoostsAndEmptyFavouritesCanBeViewed() {
        let app = launch("boosts")
        defer { app.terminate() }
        let entry = app.buttons["statusDetail.viewEngagement"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["profile.connection.sora"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["engagement.tab.boosts"].isSelected)
        app.buttons["engagement.tab.favourites"].tap()
        XCTAssertTrue(app.staticTexts["暂无可显示的账号"].waitForExistence(timeout: 5))
    }

    func testNoEntryWhenPostOnlyHasReplies() {
        let app = launch("none")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "龟背竹")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["statusDetail.viewEngagement"].exists)
    }

    func testSourceNoteWhenCountsExceedVisibleAccounts() {
        let app = launch("partial")
        defer { app.terminate() }
        let entry = app.buttons["statusDetail.viewEngagement"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()

        let note = app.staticTexts[sourceNote]
        let accounts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.connection."))
        XCTAssertTrue(app.buttons["profile.connection.yuki"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["engagement.tab.favourites"].label, "喜欢 24")
        XCTAssertEqual(accounts.count, 1)
        XCTAssertTrue(note.isHittable)
        capture(app, "06-partial-favourites")

        let boosts = app.buttons["engagement.tab.boosts"]
        XCTAssertEqual(boosts.label, "转发 6")
        boosts.tap()
        XCTAssertTrue(app.staticTexts["暂无可显示的账号"].waitForExistence(timeout: 5))
        XCTAssertEqual(accounts.count, 0)
        XCTAssertTrue(note.isHittable)
        capture(app, "07-partial-boosts")
    }

    func testEntryAndSheetAtLargeTextInDarkMode() {
        let app = launch("both", darkAndLargeText: true)
        defer { app.terminate() }
        let entry = app.buttons["statusDetail.viewEngagement"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(entry.isHittable)
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
        XCTAssertLessThanOrEqual(entry.frame.maxX, app.windows.firstMatch.frame.maxX)
        entry.tap()
        let boosts = app.buttons["engagement.tab.boosts"]
        XCTAssertTrue(boosts.waitForExistence(timeout: 5))
        boosts.tap()
        let firstAccount = app.buttons["profile.connection.sora"]
        XCTAssertTrue(firstAccount.waitForExistence(timeout: 5))
        let note = app.staticTexts[sourceNote]
        XCTAssertTrue(note.isHittable)
        XCTAssertLessThanOrEqual(firstAccount.frame.maxY, note.frame.minY)
        XCTAssertLessThan(boosts.frame.midY, app.windows.firstMatch.frame.midY)
        capture(app, "05-dark")
    }

    private func launch(_ mode: String, darkAndLargeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_THREAD_READING", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_POST_INTERACTIONS"] = mode
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = darkAndLargeText ? "dark" : "light"
        if darkAndLargeText {
            app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch(isolatedFor: self)
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "post-engagement-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
