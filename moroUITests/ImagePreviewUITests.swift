import XCTest

@MainActor
final class ImagePreviewUITests: XCTestCase {
    func testNoAltPanelAndSingleTapControls() {
        let app = launch()
        defer { app.terminate() }
        XCTAssertFalse(app.buttons["imagePreview.alt"].exists)
        XCTAssertFalse(app.staticTexts["No ALT description"].exists)
        XCTAssertFalse(app.staticTexts["没有 ALT 描述"].exists)
        attach(app, "long-image-overview-no-alt")
        center(app).tap()
        XCTAssertTrue(app.buttons["imagePreview.close"].waitForNonExistence(timeout: 3))
        center(app).tap()
        XCTAssertTrue(app.buttons["imagePreview.close"].waitForExistence(timeout: 3))
    }

    func testAltSheetPreservesZoomAndReadingPosition() {
        let app = launch(index: 1)
        defer { app.terminate() }
        center(app).doubleTap()
        let image = app.images["imagePreview.image"].firstMatch
        waitForZoom(image)
        center(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        center(app).tap()
        let alt = app.buttons["imagePreview.alt"]
        XCTAssertTrue(alt.waitForExistence(timeout: 3))
        let zoom = image.value as? String
        let frame = image.frame
        alt.tap()
        XCTAssertTrue(app.staticTexts["imagePreview.altText"].waitForExistence(timeout: 3))
        attach(app, "alt-description-sheet")
        app.buttons["imagePreview.altClose"].tap()
        XCTAssertTrue(alt.waitForExistence(timeout: 3))
        XCTAssertEqual(image.value as? String, zoom)
        XCTAssertEqual(image.frame.minY, frame.minY, accuracy: 2)
        attach(app, "reading-position-after-alt")
    }

    func testShortAltFitsContentAndCanCloseOrSwipeAway() {
        let app = launch(index: 1, altText: "一只橘猫趴在窗边，午后的阳光落在它的耳朵上。")
        defer { app.terminate() }
        let sheet = openAltSheet(app)
        assertAltHeader(app)
        XCTAssertLessThan(sheet.frame.height, 300)
        assertAltTextFits(app, sheet: sheet)
        attach(app, "alt-short-light")

        app.buttons["imagePreview.altClose"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["imagePreview.alt"].isHittable)
        _ = openAltSheet(app)
        app.staticTexts["imagePreview.altTitle"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["imagePreview.close"].isHittable)
    }

    func testMediumAltHasNoRedundantTitleOrEmptyHalfSheet() {
        let description = "一张复古风格的招聘海报。米白色方格纸上写着大大的 NEED YOU 和「寻找小伙伴」，"
            + "下面用蓝绿色纸片介绍团队。右上角贴着黄色波浪纹胶带，中间画了一只小喇叭。"
            + "海报下方列出开放的职位、工作地点和联系方式，边缘保留了剪贴纸张的纹理，整体像一本手工拼贴日记。"
        let app = launch(index: 1, altText: description)
        defer { app.terminate() }
        let sheet = openAltSheet(app)
        assertAltHeader(app)
        XCTAssertLessThan(sheet.frame.height, app.frame.height * 0.48)
        assertAltTextFits(app, sheet: sheet)
        attach(app, "alt-medium-light")
        app.buttons["imagePreview.altClose"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
    }

    func testLongAltCanExpandScrollAndKeepCloseReachable() {
        let app = launch(index: 1)
        defer { app.terminate() }
        let sheet = openAltSheet(app)
        assertAltHeader(app)
        let initialHeight = sheet.frame.height
        XCTAssertLessThan(initialHeight, app.frame.height * 0.68)
        attach(app, "alt-long-collapsed")
        app.staticTexts["imagePreview.altTitle"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        XCTAssertGreaterThan(sheet.frame.height, initialHeight + 100)
        let scroll = app.scrollViews["imagePreview.altScroll"]
        for _ in 0..<3 { scroll.swipeUp() }
        XCTAssertLessThanOrEqual(app.staticTexts["imagePreview.altText"].frame.maxY, scroll.frame.maxY + 2)
        XCTAssertTrue(app.buttons["imagePreview.altClose"].isHittable)
        attach(app, "alt-long-expanded-at-end")
        app.buttons["imagePreview.altClose"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
    }

    func testAltDarkModeAndAccessibilityTextKeepHeaderUsable() {
        let app = launch(index: 1,
            altText: "夕阳映在海面上，几只海鸥掠过粉橙色的天空，远处是灯塔的剪影。",
            environment: ["UITEST_COLOR_SCHEME": "dark", "UITEST_DYNAMIC_TYPE_SIZE": "accessibilityXXXL"])
        defer { app.terminate() }
        let sheet = openAltSheet(app)
        assertAltHeader(app)
        let title = app.staticTexts["imagePreview.altTitle"]
        let text = app.staticTexts["imagePreview.altText"]
        XCTAssertGreaterThan(title.frame.height, 35)
        XCTAssertGreaterThan(text.frame.minY, title.frame.maxY)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.buttons["imagePreview.altClose"].frame.minX)
        attach(app, "alt-dark-accessibility-text")
        app.buttons["imagePreview.altClose"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
    }

    func testLongImageZoomAndPanDoNotDismissOrChangePage() {
        let app = launch()
        defer { app.terminate() }
        center(app).doubleTap()
        let image = app.images["imagePreview.image"].firstMatch
        waitForZoom(image)
        XCTAssertEqual(image.frame.width, app.frame.width, accuracy: 2)
        center(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(image.exists)
        center(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        center(app).tap()
        XCTAssertTrue(app.staticTexts["imagePreview.page"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["imagePreview.page"].label, "1 / 3")
        attach(app, "long-image-width-reading")
    }

    func testSlowShortDragsReturnToTheSameOverviewAndStillAllowPaging() {
        let app = launch()
        defer { app.terminate() }
        let image = app.images["imagePreview.image"].firstMatch
        let originalFrame = image.frame
        for distance: CGFloat in [12, 24, 50] {
            center(app).press(forDuration: 0.1,
                thenDragTo: center(app).withOffset(CGVector(dx: 0, dy: distance)),
                withVelocity: XCUIGestureVelocity(rawValue: 40), thenHoldForDuration: 0.2)
            expectation(for: NSPredicate { _, _ in
                abs(image.frame.minY - originalFrame.minY) < 1
                    && abs(image.frame.height - originalFrame.height) < 1
            }, evaluatedWith: image)
            waitForExpectations(timeout: 4)
            XCTAssertEqual(image.value as? String, "100%")
        }
        center(app).tap()
        XCTAssertEqual(app.staticTexts["imagePreview.page"].label, "1 / 3")
        app.swipeLeft()
        XCTAssertTrue(app.buttons["imagePreview.alt"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["imagePreview.page"].label, "2 / 3")
        attach(app, "short-drags-preserve-viewport-and-paging")
    }

    func testShortPanAtReadingScaleDoesNotJumpOrDismiss() {
        let app = launch()
        defer { app.terminate() }
        center(app).doubleTap()
        let image = app.images["imagePreview.image"].firstMatch
        waitForZoom(image)
        let zoom = image.value as? String
        let originalFrame = image.frame
        center(app).press(forDuration: 0.1,
            thenDragTo: center(app).withOffset(CGVector(dx: 0, dy: -24)),
            withVelocity: XCUIGestureVelocity(rawValue: 40), thenHoldForDuration: 0.3)
        XCTAssertTrue(image.exists)
        XCTAssertEqual(image.value as? String, zoom)
        XCTAssertEqual(image.frame.width, originalFrame.width, accuracy: 1)
        // Native pan recognition has a small touch slop; reject a viewport-size
        // jump while allowing that system threshold and subpixel rounding.
        let displacement = originalFrame.minY - image.frame.minY
        XCTAssertGreaterThan(displacement, 5)
        XCTAssertLessThanOrEqual(displacement, 26)
        center(app).tap()
        XCTAssertEqual(app.staticTexts["imagePreview.page"].label, "1 / 3")
    }

    func testPagingUpdatesAltAndOverviewCanDismiss() {
        let app = launch()
        defer { app.terminate() }
        app.swipeLeft()
        XCTAssertTrue(app.buttons["imagePreview.alt"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["imagePreview.page"].label, "2 / 3")
        app.swipeLeft()
        let page = app.staticTexts["imagePreview.page"]
        expectation(for: NSPredicate(format: "label == '3 / 3'"), evaluatedWith: page)
        waitForExpectations(timeout: 4)
        XCTAssertFalse(app.buttons["imagePreview.alt"].exists)
        attach(app, "wide-image-blank-alt")
        center(app).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["imagePreview.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["imagePreview.close"].exists)
    }

    func testPinchZoomRemainsInteractiveAndReturnsToOverview() {
        let app = launch(index: 2)
        defer { app.terminate() }
        let image = app.images["imagePreview.image"].firstMatch
        image.pinch(withScale: 2, velocity: 1)
        waitForZoom(image)
        image.pinch(withScale: 0.4, velocity: -1)
        expectation(for: NSPredicate(format: "value == '100%'"), evaluatedWith: image)
        waitForExpectations(timeout: 5)
        center(app).tap()
        XCTAssertTrue(app.buttons["imagePreview.close"].waitForExistence(timeout: 3))
        app.buttons["imagePreview.close"].tap()
        XCTAssertTrue(app.buttons["imagePreview.open"].waitForExistence(timeout: 5))
    }

    func testLongImageCanReachItsBottomWithoutAnOverlay() {
        let app = launch()
        defer { app.terminate() }
        center(app).doubleTap()
        let image = app.images["imagePreview.image"].firstMatch
        waitForZoom(image)
        for _ in 0..<5 { app.swipeUp() }
        XCTAssertFalse(app.buttons["imagePreview.close"].exists)
        XCTAssertFalse(app.buttons["imagePreview.alt"].exists)
        XCTAssertLessThanOrEqual(image.frame.maxY, app.frame.maxY + 2)
        XCTAssertGreaterThan(image.frame.maxY, app.frame.maxY - 60)
        attach(app, "long-image-bottom-unobscured")
    }

    func testShareButtonAndLongPressActionsLeaveTheImageUncovered() {
        let app = launch(index: 1)
        defer { app.terminate() }
        let share = app.buttons["imagePreview.share"]
        XCTAssertTrue(share.isHittable)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        // Chrome stays in the top bar: nothing is pinned over the image's lower half.
        XCTAssertLessThan(share.frame.maxY, app.frame.height * 0.2)
        XCTAssertLessThan(app.buttons["imagePreview.alt"].frame.maxY, app.frame.height * 0.2)
        attach(app, "preview-top-bar-with-share")

        center(app).press(forDuration: 0.8)
        let copy = app.buttons["拷贝"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["保存到相册"].exists)
        XCTAssertTrue(app.buttons["分享…"].exists)
        attach(app, "preview-long-press-actions")
        copy.tap()
        let notice = app.staticTexts["imagePreview.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.label, "已拷贝图片")
        XCTAssertTrue(notice.waitForNonExistence(timeout: 5))
        // The long press must not have zoomed, paged or dismissed.
        XCTAssertEqual(app.images["imagePreview.image"].firstMatch.value as? String, "100%")
        XCTAssertEqual(app.staticTexts["imagePreview.page"].label, "2 / 3")
    }

    private func launch(index: Int = 0, altText: String? = nil,
        environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_IMAGE_PREVIEW", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UITEST_IMAGE_INDEX"] = String(index)
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = "light"
        app.launchEnvironment["UITEST_ALT_TEXT"] = altText
        app.launchEnvironment.merge(environment) { _, override in override }
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.buttons["imagePreview.close"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.images["imagePreview.image"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func openAltSheet(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["imagePreview.alt"].tap()
        let sheet = app.otherElements["imagePreview.altSheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["imagePreview.altText"].waitForExistence(timeout: 3))
        return sheet
    }

    private func assertAltHeader(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "图片描述")).count, 1,
            file: file, line: line)
        let close = app.buttons["imagePreview.altClose"]
        XCTAssertTrue(close.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44, file: file, line: line)
    }

    private func assertAltTextFits(_ app: XCUIApplication, sheet: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts["imagePreview.altText"]
        XCTAssertLessThanOrEqual(text.frame.maxY, sheet.frame.maxY, file: file, line: line)
        XCTAssertLessThan(sheet.frame.maxY - text.frame.maxY, 70, file: file, line: line)
        XCTAssertGreaterThan(text.frame.minY, app.staticTexts["imagePreview.altTitle"].frame.maxY,
            file: file, line: line)
    }

    private func center(_ app: XCUIApplication) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    private func waitForZoom(_ image: XCUIElement) {
        expectation(for: NSPredicate(format: "value != '100%' AND value != nil"), evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
