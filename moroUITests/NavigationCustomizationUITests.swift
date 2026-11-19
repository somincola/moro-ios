import XCTest

@MainActor
final class NavigationCustomizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDragOrderPersistsAndSwitchingAccountsKeepsSeparateLayouts() {
        let app = launch()
        defer { app.terminate() }
        openEditorFromProfile(app)
        XCTAssertEqual(app.staticTexts["navigationCustomization.account"].label, "@viewer@push-a.push-fixture.invalid")
        XCTAssertFalse(app.buttons["navigationCustomization.restore"].isEnabled)

        tap(choice("bookmarks", in: app))
        XCTAssertFalse(choice("favourites", in: app).isEnabled)
        tap(choice("explore", in: app))
        tap(choice("favourites", in: app))

        let home = preview("home", in: app)
        let me = preview("me", in: app)
        XCTAssertTrue(me.waitForExistence(timeout: 5))
        XCTAssertEqual(home.label, "Home")
        me.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.2, thenDragTo: home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        )
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Position 1 of 5"), object: me
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "navigation-customization"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        closeEditorAndSettings(app)

        let order = ["me", "home", "inbox", "bookmarks", "favourites"]
        assertTabOrder(order, in: app)
        XCTAssertFalse(tab("explore", in: app).exists)
        XCTAssertTrue(tab("inbox", in: app).wait(for: \.label, toEqual: "Inbox, 2 unread", timeout: 10))
        tap(tab("favourites", in: app))
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Navigation favourite fixture"].waitForExistence(timeout: 5))
        XCTAssertEqual(tab("favourites", in: app).label, "Favourites")
        let tabBarScreenshot = XCTAttachment(screenshot: app.tabBars.firstMatch.screenshot())
        tabBarScreenshot.name = "customized-tab-bar"
        tabBarScreenshot.lifetime = .keepAlways
        add(tabBarScreenshot)

        switchAccount("push-b", in: app)
        XCTAssertTrue(tab("explore", in: app).waitForExistence(timeout: 10))
        assertTabOrder(["home", "explore", "inbox", "me"], in: app)
        XCTAssertFalse(tab("favourites", in: app).exists)
        switchAccount("push-a", in: app)
        assertTabOrder(order, in: app)

        app.terminate()
        app.launch(isolatedFor: self)
        assertTabOrder(order, in: app)

        openEditorFromProfile(app)
        tap(app.buttons["navigationCustomization.restore"])
        XCTAssertFalse(app.buttons["navigationCustomization.restore"].isEnabled)
        closeEditorAndSettings(app)
        assertTabOrder(["home", "explore", "inbox", "me"], in: app)
    }

    func testOptionalRootsOpenExistingPagesAndCanRemoveTheSettingsTab() {
        let app = launch()
        defer { app.terminate() }
        openEditorFromProfile(app)
        tap(choice("explore", in: app))
        tap(choice("lists", in: app))
        tap(choice("settings", in: app))
        closeEditorAndSettings(app)

        tap(tab("lists", in: app))
        XCTAssertTrue(app.navigationBars["Lists"].waitForExistence(timeout: 5))
        tap(app.buttons["lists.row.nav-list"])
        XCTAssertTrue(app.navigationBars["Navigation list fixture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Navigation list post fixture"].waitForExistence(timeout: 5))
        tap(app.navigationBars.buttons.firstMatch)

        tap(tab("settings", in: app))
        tap(app.buttons["settings.display"])
        openCustomization(in: app)
        tap(choice("settings", in: app))
        XCTAssertTrue(app.navigationBars["Customize Navigation"].exists)
        tap(choice("bookmarks", in: app))
        tap(app.buttons["navigationCustomization.done"])
        XCTAssertTrue(tab("home", in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertFalse(tab("settings", in: app).exists)

        tap(tab("bookmarks", in: app))
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Navigation bookmark fixture"].waitForExistence(timeout: 5))

        tap(tab("me", in: app))
        tap(app.buttons["profile.moreButton"])
        tap(app.buttons["profile.menu.explore"])
        XCTAssertTrue(app.searchFields["search.input"].waitForExistence(timeout: 5))
    }

    func testThreeColumnChoicesAllowHidingInboxAndMeAndKeepPushesReachable() {
        let app = launch(inChinese: true)
        defer { app.terminate() }
        openEditorFromProfile(app, title: "自定义导航", checkAppearanceLayout: true)
        let home = choice("home", in: app)
        let explore = choice("explore", in: app)
        let inbox = choice("inbox", in: app)
        let me = choice("me", in: app)
        XCTAssertEqual(home.frame.minY, explore.frame.minY, accuracy: 1)
        XCTAssertEqual(home.frame.minY, inbox.frame.minY, accuracy: 1)
        XCTAssertLessThan(home.frame.maxX, explore.frame.minX)
        XCTAssertLessThan(explore.frame.maxX, inbox.frame.minX)
        XCTAssertEqual(me.frame.minX, home.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(me.frame.minY, home.frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "navigation-three-column-zh"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        tap(inbox)
        tap(me)
        XCTAssertFalse(home.isEnabled)
        XCTAssertFalse(explore.isEnabled)
        XCTAssertEqual(preview("explore", in: app).value as? String, "第 2 位，共 2 位")
        tap(inbox)
        XCTAssertTrue(explore.isEnabled)
        XCTAssertEqual(preview("inbox", in: app).value as? String, "第 3 位，共 3 位")
        tap(inbox)
        closeEditorAndSettings(app)
        assertTabOrder(["home", "explore"], in: app)
        XCTAssertFalse(tab("me", in: app).exists)
        XCTAssertFalse(tab("inbox", in: app).exists)

        // Opening an external notification on relaunch should keep the two saved tabs.
        app.terminate()
        app.launchEnvironment["UITEST_PUSH_SCENARIO"] = "post"
        app.launchArguments.removeAll { $0 == "UITEST_DISABLE_ANIMATIONS" }
        app.launch(isolatedFor: self)
        let post = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Push target post on push-a.push-fixture.invalid")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 12))
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'BackButton' OR label == '返回'")).firstMatch
        tap(back)
        tap(app.buttons["inbox.filter.mentions"])
        XCTAssertTrue(app.buttons["inbox.filter.mentions"].isSelected)
        tap(back)
        assertTabOrder(["home", "explore"], in: app)
        tap(app.buttons["设置"])
        tap(app.buttons["settings.display"])
        openCustomization(in: app)
        tap(app.buttons["navigationCustomization.restore"])
        closeEditorAndSettings(app)
        assertTabOrder(["home", "explore", "inbox", "me"], in: app)
    }

    private func launch(inChinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_PUSH_OPEN", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", inChinese ? "(zh-Hans)" : "(en)", "-AppleLocale", inChinese ? "zh_CN" : "en_US",
        ]
        app.launchEnvironment["UITEST_PUSH_SCENARIO"] = "inbox"
        app.launchEnvironment["UITEST_SWITCHER_ACCOUNTS"] = "1"
        app.launchEnvironment["UITEST_NOTIFICATIONS_UNREAD"] = "2"
        app.launch(isolatedFor: self)
        return app
    }

    private func openEditorFromProfile(_ app: XCUIApplication, title: String = "Customize Navigation",
        checkAppearanceLayout: Bool = false) {
        tap(tab("me", in: app))
        tap(app.buttons["profile.moreButton"])
        tap(app.buttons["profile.settings"])
        tap(app.buttons["settings.display"])
        openCustomization(in: app, checkAppearanceLayout: checkAppearanceLayout)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    private func openCustomization(in app: XCUIApplication, checkAppearanceLayout: Bool = false) {
        let link = app.buttons["settings.navigationCustomization"]
        let icon = app.buttons["settings.appIcon"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<5 where !icon.isHittable || icon.frame.maxY > app.windows.firstMatch.frame.maxY - 65 {
            list.swipeUp()
        }
        if checkAppearanceLayout {
            let navigationRow = list.cells.containing(.button, identifier: "settings.navigationCustomization").firstMatch
            let appIconRow = list.cells.containing(.button, identifier: "settings.appIcon").firstMatch
            XCTAssertTrue(link.isHittable && icon.isHittable)
            XCTAssertEqual(navigationRow.frame.maxY, appIconRow.frame.minY, accuracy: 2)
            XCTAssertTrue(app.staticTexts["导航布局按账号保存。其他外观设置在此设备上共享。"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "appearance-navigation-and-app-icon-zh"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        tap(link)
    }

    private func closeEditorAndSettings(_ app: XCUIApplication) {
        tap(app.navigationBars.buttons.firstMatch)
        tap(app.navigationBars.buttons.firstMatch)
        tap(app.buttons["settings.sheet.close"])
    }

    private func switchAccount(_ id: String, in app: XCUIApplication) {
        let me = tab("me", in: app)
        XCTAssertTrue(me.waitForExistence(timeout: 10))
        me.press(forDuration: 0.6)
        tap(app.descendants(matching: .any)["accountSwitcher.account.\(id)"])
    }

    private func assertTabOrder(_ tabs: [String], in app: XCUIApplication) {
        var lastX: CGFloat = 0
        for name in tabs {
            let item = tab(name, in: app)
            XCTAssertTrue(item.waitForExistence(timeout: 10), name)
            XCTAssertGreaterThan(item.frame.midX, lastX, name)
            lastX = item.frame.midX
        }
    }

    private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let identifier = "mainTab.\(name)"
        let chinese = app.launchArguments.contains("(zh-Hans)")
        let titles = [
            "home": chinese ? "首页" : "Home", "explore": chinese ? "发现" : "Explore",
            "inbox": chinese ? "收件箱" : "Inbox", "me": chinese ? "我" : "Me",
            "lists": "Lists", "bookmarks": "Bookmarks",
            "favourites": "Favourites", "settings": "Settings",
        ]
        if let title = titles[name] {
            return app.tabBars.buttons.matching(
                NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", identifier, title)
            ).firstMatch
        }
        return app.buttons[identifier]
    }

    private func choice(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["navigationCustomization.choice.\(name)"]
    }

    private func preview(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["navigationCustomization.preview.\(name)"]
    }

    private func tap(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 8), file: file, line: line)
        item.tap()
    }
}
