import XCTest

final class ThreadReadingUITests: XCTestCase {
    @MainActor func testThreadReadingInLightMode() { verifyFlow(scheme: "light") }
    @MainActor func testThreadReadingInDarkMode() { verifyFlow(scheme: "dark") }
    @MainActor func testThreadReadingAtAccessibilityTextSize() { verifyFlow(scheme: "light", largeText: true) }
    @MainActor func testSuppliedThreadInLightMode() { verifySuppliedThread(scheme: "light") }
    @MainActor func testSuppliedThreadInDarkMode() { verifySuppliedThread(scheme: "dark") }

    @MainActor private func verifyFlow(scheme: String, largeText: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_THREAD_READING", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        }
        app.launch()
        defer { app.terminate() }
        let menu = app.buttons["thread.readingOptions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        let branch = app.buttons["thread.branch.a"]
        reveal(branch, app: app)
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
        // Compact rows can leave the first expanded reply below the viewport.
        reveal(app.otherElements["thread.row.a1"], app: app)
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
        app.launch()
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
        for _ in 0..<24 where !element.isHittable {
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
