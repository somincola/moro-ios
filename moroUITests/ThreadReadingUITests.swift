import XCTest

final class ThreadReadingUITests: XCTestCase {
    @MainActor func testThreadReadingInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testThreadReadingInDarkMode() { verifyFlow(scheme: "dark") }
    @MainActor func testThreadReadingAtAccessibilityTextSize() { verifyFlow(scheme: "light", largeText: true) }
    @MainActor func testSuppliedThreadInLightMode() { verifySuppliedThread(scheme: "light") }
    @MainActor func testSuppliedThreadInDarkMode() { verifySuppliedThread(scheme: "dark") }

    @MainActor func testBoostDialogInLightMode() { verifyBoostDialog(scheme: "light") }
    @MainActor func testBoostDialogInDarkMode() { verifyBoostDialog(scheme: "dark") }
    @MainActor func testBoostDialogAtLargestTextSize() { verifyBoostDialog(scheme: "light", largeText: true) }
    @MainActor func testQuoteFromMoreMenuWithConfirmationOffInLightMode() {
        verifyBoostDialog(scheme: "light", askBeforeBoosting: false)
    }
    @MainActor func testQuoteFromMoreMenuWithConfirmationOffInDarkMode() {
        verifyBoostDialog(scheme: "dark", askBeforeBoosting: false)
    }

    @MainActor private func verifyBoostDialog(scheme: String, largeText: Bool = false, askBeforeBoosting: Bool = true) {
        continueAfterFailure = false
        let app = XCUIApplication()
        let settingsArguments = [
            "UITEST_SETTINGS_SHEET", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launchArguments = settingsArguments
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.buttons["settings.posting"].waitForExistence(timeout: 5))
        app.buttons["settings.posting"].tap()
        let confirmation = app.switches["Ask before boosting posts"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let original = confirmation.value as? String ?? ""
        XCTAssertTrue(["0", "Off", "1", "On"].contains(original))
        let changedPreference = ["1", "On"].contains(original) != askBeforeBoosting
        if changedPreference { confirmation.tap() }
        app.terminate()
        defer {
            app.terminate()
            if changedPreference {
                app.launchArguments = settingsArguments
                app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = nil
                app.launch(isolatedFor: self)
                XCTAssertTrue(app.buttons["settings.posting"].waitForExistence(timeout: 5))
                app.buttons["settings.posting"].tap()
                XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
                if confirmation.value as? String != original { confirmation.tap() }
                app.terminate()
            }
        }
        app.launchArguments = [
            "UITEST_THREAD_READING", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
        ]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        if largeText {
            app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL"
        }
        app.launch(isolatedFor: self)
        let trigger = app.buttons.matching(identifier: "转发").element(boundBy: 1)
        XCTAssertTrue(trigger.waitForExistence(timeout: 10))
        reveal(trigger, app: app)
        trigger.tap()
        let boost = app.buttons["boostDialog.boost"]
        let quote = app.buttons["boostDialog.quote"]
        if askBeforeBoosting {
            XCTAssertTrue(boost.waitForExistence(timeout: 5))
            XCTAssertTrue(quote.exists)
            XCTAssertEqual(boost.label, "转发")
            XCTAssertEqual(quote.label, "引用")
            for row in [boost, quote] {
                XCTAssertTrue(row.isHittable)
                XCTAssertGreaterThanOrEqual(row.frame.height, 44)
                XCTAssertGreaterThanOrEqual(row.frame.minX, 0)
                XCTAssertLessThanOrEqual(row.frame.maxX, app.windows.firstMatch.frame.maxX)
            }
            if largeText { XCTAssertGreaterThan(boost.frame.height, 90) }
            attach(app, "boost-dialog-\(scheme)-\(largeText ? "largest" : "standard")")
            quote.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        } else {
            XCTAssertTrue(app.buttons.matching(identifier: "取消转发").firstMatch.waitForExistence(timeout: 8))
            XCTAssertFalse(boost.exists)
            app.buttons.matching(identifier: "post.more.focus").element(boundBy: 1).tap()
            let menuQuote = app.buttons["post.quote.focus"]
            XCTAssertTrue(menuQuote.waitForExistence(timeout: 5))
            XCTAssertEqual(menuQuote.label, "引用")
            attach(app, "quote-more-menu-\(scheme)")
            menuQuote.tap()
        }
        XCTAssertTrue(app.buttons["compose.audienceMenu"].waitForExistence(timeout: 8))
        XCTAssertFalse(quote.exists)
    }

    @MainActor private func verifyFlow(scheme: String, largeText: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_THREAD_READING", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        }
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        let menu = app.buttons["thread.readingOptions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        let focusedBody = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "当前帖子：")
        ).firstMatch
        XCTAssertTrue(focusedBody.waitForExistence(timeout: 5))
        XCTAssertEqual(focusedBody.frame.minX, 16, accuracy: 1)
        let branch = app.buttons["thread.branch.a"]
        reveal(branch, app: app)
        let replyBody = app.staticTexts["回复 a"]
        XCTAssertTrue(replyBody.waitForExistence(timeout: 5))
        XCTAssertEqual(replyBody.frame.minX, 72, accuracy: 1)
        assertFullWidthControl(branch, app: app)
        attach(app, "thread-control-expanded-\(scheme)")
        let controlY = branch.frame.minY
        // Empty space near either edge must activate the same full-row control.
        branch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(branch.label.contains("展开 3"))
        XCTAssertEqual(branch.frame.minY, controlY, accuracy: 1)
        XCTAssertFalse(app.otherElements["thread.row.a1"].exists)
        XCTAssertFalse(app.buttons["thread.parent.a1"].exists)
        attach(app, "thread-collapsed-\(scheme)")
        branch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        XCTAssertTrue(branch.label.contains("收起 3"))
        XCTAssertEqual(branch.frame.minY, controlY, accuracy: 1)
        XCTAssertTrue(app.otherElements["thread.row.a1"].waitForExistence(timeout: 5))
        // Reply metadata stays out of the reading column, including after expanding.
        XCTAssertFalse(app.buttons["thread.parent.a1"].exists)
        XCTAssertFalse(app.buttons["thread.branch.a1"].exists)
        menu.tap()
        app.buttons["thread.authorOnly"].tap()
        XCTAssertTrue(app.staticTexts["thread.authorOnlyHint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thread.branch.a"].exists)
        attach(app, "thread-author-only-\(scheme)")
        XCTAssertFalse(app.buttons["thread.parent.a1"].exists)
        menu.tap()
        app.buttons["thread.authorOnly"].tap()
        XCTAssertFalse(app.staticTexts["thread.authorOnlyHint"].exists)
        app.scrollViews.firstMatch.swipeUp()
        menu.tap()
        app.buttons["thread.returnToPost"].tap()
        let focused = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "当前帖子：")).firstMatch
        XCTAssertTrue(focused.waitForExistence(timeout: 5))
        XCTAssertTrue(focused.isHittable)
        reveal(branch, app: app)
        XCTAssertTrue(branch.label.contains("收起 3"))
        let shortReply = app.staticTexts["回复 short2"]
        reveal(shortReply, app: app)
        XCTAssertFalse(app.buttons["thread.branch.short"].exists)
        XCTAssertFalse(app.buttons["thread.branch.short1"].exists)
        attach(app, "thread-short-discussion-\(scheme)")
    }

    @MainActor private func verifySuppliedThread(scheme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_THREAD_READING", "UITEST_THREAD_REAL_SAMPLE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        let menu = app.buttons["thread.readingOptions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        attach(app, "thread-sample-original-\(scheme)")
        XCTAssertFalse(app.staticTexts["thread.authorContinuations"].exists)
        XCTAssertFalse(app.staticTexts["thread.replies"].exists)
        let opening = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "因为太震撼了")).firstMatch
        reveal(opening, app: app)
        let contentLeadingEdge = opening.frame.minX
        let child = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "她妈以前一直")).firstMatch
        reveal(child, app: app)
        XCTAssertEqual(child.frame.minX, contentLeadingEdge, accuracy: 1)
        let sibling = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "另一个朋友贡献了")).firstMatch
        reveal(sibling, app: app)
        XCTAssertEqual(sibling.frame.minX, contentLeadingEdge, accuracy: 1)
        XCTAssertFalse(app.buttons["thread.parent.117118126512386830"].exists)
        attach(app, "thread-sample-additions-\(scheme)")
        let branch = app.buttons["thread.branch.117116945719580606"]
        reveal(branch, app: app)
        XCTAssertTrue(branch.label.contains("收起 7"))
        assertFullWidthControl(branch, app: app)
        attach(app, "thread-sample-discussion-\(scheme)")
        let controlY = branch.frame.minY
        branch.tap()
        XCTAssertTrue(branch.label.contains("展开 7"))
        XCTAssertEqual(branch.frame.minY, controlY, accuracy: 1)
        XCTAssertFalse(app.otherElements["thread.row.117116973265571189"].exists)
        attach(app, "thread-sample-collapsed-\(scheme)")
        branch.tap()
        XCTAssertEqual(branch.frame.minY, controlY, accuracy: 1)
        XCTAssertTrue(app.otherElements["thread.row.117116973265571189"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thread.branch.117116973265571189"].exists)

        // A deeper fork keeps the same reading layout without an extra parent header.
        let fork = app.otherElements["thread.row.117117388752166120"]
        reveal(fork, app: app)
        XCTAssertFalse(app.buttons["thread.parent.117117388752166120"].exists)
        attach(app, "thread-sample-reply-fork-\(scheme)")

        // The author's response to a reader belongs to that reader's discussion too.
        let readerBranch = app.buttons["thread.branch.117117689679969635"]
        reveal(readerBranch, app: app)
        XCTAssertTrue(readerBranch.label.contains("收起 3"))
        let readerControlY = readerBranch.frame.minY
        attach(app, "thread-reader-three-expanded-\(scheme)")
        readerBranch.tap()
        XCTAssertTrue(readerBranch.label.contains("展开 3"))
        XCTAssertEqual(readerBranch.frame.minY, readerControlY, accuracy: 1)
        XCTAssertTrue(app.otherElements["thread.row.117117689679969635"].exists)
        for replyID in ["117117695638809878", "117118009864271692", "117118175009985659"] {
            XCTAssertFalse(app.otherElements["thread.row.\(replyID)"].exists)
            XCTAssertFalse(app.buttons["thread.branch.\(replyID)"].exists)
        }
        attach(app, "thread-reader-three-collapsed-\(scheme)")
        readerBranch.tap()
        XCTAssertTrue(readerBranch.label.contains("收起 3"))
        XCTAssertEqual(readerBranch.frame.minY, readerControlY, accuracy: 1)
        let authorReply = app.otherElements["thread.row.117117695638809878"]
        reveal(authorReply, app: app)
        XCTAssertFalse(app.buttons["thread.branch.117117695638809878"].exists)
        reveal(app.otherElements["thread.row.117118009864271692"], app: app)
        reveal(app.otherElements["thread.row.117118175009985659"], app: app)
        attach(app, "thread-reader-three-restored-\(scheme)")

        menu.tap()
        app.buttons["thread.authorOnly"].tap()
        XCTAssertTrue(app.staticTexts["thread.authorOnlyHint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thread.branch.117116945719580606"].exists)
        menu.tap()
        app.buttons["thread.returnToPost"].tap()
        let focused = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "一直以为我老家村子里的老头老太们")).firstMatch
        XCTAssertTrue(focused.isHittable)
    }

    @MainActor private func assertFullWidthControl(_ button: XCUIElement, app: XCUIApplication) {
        let scrollFrame = app.scrollViews.firstMatch.frame
        XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.01)
        XCTAssertEqual(button.frame.minX, scrollFrame.minX, accuracy: 1)
        XCTAssertEqual(button.frame.width, scrollFrame.width, accuracy: 1)
    }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<24 {
            // A partially visible control can be "hittable" while its tap point
            // still falls inside the home indicator's gesture region.
            if element.isHittable && element.frame.midY < scroll.frame.maxY - 44 {
                break
            }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
