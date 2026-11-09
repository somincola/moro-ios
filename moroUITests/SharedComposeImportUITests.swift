import XCTest

@MainActor
final class SharedComposeImportUITests: XCTestCase {
    func testBatchOpensEditorAndOnlyExplicitSaveCreatesAManualDraft() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["shareFixture.stage"].tap()
        waitForSummary(app, "Manual: 0; files: 0; uploads: 2; posts: 0", editing: true)
        XCTAssertEqual(app.textViews["compose.textInput"].value as? String, "Shared words")
        XCTAssertTrue(app.composePostButton.isEnabled)
        attach(app, "share-batch-editor")
        close(app, action: "Save Draft")
        waitForSummary(app, "Manual: 1; files: 0; uploads: 2; posts: 0")
    }

    func testOpenEditorAppendsIncomingMediaAndDiscardDoesNotReopenIt() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["shareFixture.existing"].tap()
        XCTAssertTrue(app.buttons["shareFixture.incoming"].waitForExistence(timeout: 8))
        app.buttons["shareFixture.incoming"].tap()
        waitForSummary(app, "Manual: 0; files: 0; uploads: 2; posts: 0", editing: true)
        XCTAssertEqual(app.textViews["compose.textInput"].value as? String, "Existing words\n\nShared words")
        close(app, action: "Discard Draft")
        waitForSummary(app, "Manual: 0; files: 0; uploads: 2; posts: 0")
        XCTAssertFalse(app.composePostButton.exists)
    }

    func testFailedUploadRetainsTheRemainderAndRetryFinishesTheBatch() {
        let app = launch("retry")
        defer { app.terminate() }
        app.buttons["shareFixture.stage"].tap()
        let retry = app.buttons["compose.sharedImportRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        waitForSummary(app, "Manual: 0; files: 1; uploads: 2; posts: 0", editing: true)
        attach(app, "share-upload-recoverable-error")
        retry.tap()
        waitForSummary(app, "Manual: 0; files: 0; uploads: 3; posts: 0", editing: true)
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.textViews["compose.textInput"].value as? String, "Shared words")
    }

    func testOverLimitCanBeIgnoredWithoutChangingTheExistingEditor() {
        let app = launch("limit")
        defer { app.terminate() }
        app.buttons["shareFixture.existing"].tap()
        XCTAssertTrue(app.buttons["shareFixture.incoming"].waitForExistence(timeout: 8))
        app.buttons["shareFixture.incoming"].tap()
        let ignore = app.buttons["compose.sharedImportIgnore"]
        XCTAssertTrue(ignore.waitForExistence(timeout: 8))
        waitForSummary(app, "Manual: 0; files: 2; uploads: 0; posts: 0", editing: true)
        XCTAssertEqual(app.textViews["compose.textInput"].value as? String, "Existing words")
        attach(app, "share-batch-over-limit")
        ignore.tap()
        waitForSummary(app, "Manual: 0; files: 0; uploads: 0; posts: 0", editing: true)
        XCTAssertTrue(ignore.waitForNonExistence(timeout: 5))
    }

    func testSavingAFailedImportClosesItAndRestoringTheDraftResumesOnlyRemainingMedia() {
        let app = launch("retry")
        defer { app.terminate() }
        app.buttons["shareFixture.stage"].tap()
        XCTAssertTrue(app.buttons["compose.sharedImportRetry"].waitForExistence(timeout: 10))
        close(app, action: "Save Draft")
        waitForSummary(app, "Manual: 1; files: 1; uploads: 2; posts: 0")
        XCTAssertFalse(app.composePostButton.exists)
        app.buttons["shareFixture.existing"].tap()
        let drafts = app.buttons["Drafts"]
        XCTAssertTrue(drafts.waitForExistence(timeout: 6))
        drafts.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Shared words")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        waitForSummary(app, "Manual: 1; files: 0; uploads: 3; posts: 0", editing: true)
        XCTAssertEqual(app.textViews["compose.textInput"].value as? String, "Shared words")
    }

    /// The real Photos host launches the installed extension; no URL is injected by this test.
    /// Use a simulator containing sample Photos (the default simulator library is sufficient).
    func testPhotosShareReturnsDirectlyToTheAlreadyOpenEditor() throws {
        let app = launch("system")
        defer { app.terminate() }
        app.buttons["shareFixture.existing"].tap()
        XCTAssertTrue(app.textViews["compose.textInput"].waitForExistence(timeout: 8))
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.launch()
        defer { photos.terminate() }
        let welcome = photos.buttons["Continue"]
        if welcome.waitForExistence(timeout: 2) { welcome.tap() }
        let alerts = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts
        if alerts.firstMatch.waitForExistence(timeout: 2) {
            alerts.buttons.matching(NSPredicate(format: "label IN %@", ["不允许", "Don’t Allow", "Don't Allow"])).firstMatch.tap()
        }
        // The library also has an off-screen Close button in Customize Collections.
        // Only close a real single-photo viewer, never that unrelated footer.
        if photos.scrollViews["OneUpMainPagingView"].exists {
            let closePhoto = photos.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "关闭"])).firstMatch
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: closePhoto)
            waitForExpectations(timeout: 10)
            closePhoto.tap()
        }
        let photo = photos.images.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "照片,", "Photo,")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 8), "Seed the simulator Photos library before this test")
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: photo)
        waitForExpectations(timeout: 10)
        photo.tap()
        let share = photos.buttons.matching(NSPredicate(format: "label IN %@", ["Share", "分享"])).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 6))
        share.tap()
        let activity = photos.otherElements["ActivityListView"]
        if !activity.waitForExistence(timeout: 4) { share.tap() }
        XCTAssertTrue(activity.waitForExistence(timeout: 6))
        let moro = activity.descendants(matching: .any)["Moro"].firstMatch
        let more = activity.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["More", "更多"])).firstMatch
        if !moro.waitForExistence(timeout: 3), more.exists { more.tap() }
        XCTAssertTrue(moro.waitForExistence(timeout: 6))
        moro.tap()
        // Do not call app.activate(): the extension itself must bring Moro forward.
        expectation(for: NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue), evaluatedWith: app)
        waitForExpectations(timeout: 15)
        let alt = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "compose.media.alt.")).firstMatch
        XCTAssertTrue(alt.waitForExistence(timeout: 15))
        XCTAssertEqual(app.textViews["compose.textInput"].value as? String, "Existing words")
        attach(app, "photos-direct-handoff-existing-editor")
        close(app, action: "Discard Draft")
        waitForSummary(app, "Manual: 0; files: 0; uploads: 1; posts: 0")
    }

    func testTwoPhotosOpenANewEditorAndCanBeSavedAsADraft() {
        let app = launch("system")
        defer { app.terminate() }
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        // A fresh Photos host clears the previous share sheet's cached presentation.
        photos.launch()
        defer { photos.terminate() }
        let select = photos.buttons.matching(NSPredicate(format: "label IN %@", ["Select", "选择"])).firstMatch
        let closePhoto = photos.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "关闭"])).firstMatch
        if !select.waitForExistence(timeout: 3), closePhoto.exists {
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: closePhoto)
            waitForExpectations(timeout: 10)
            closePhoto.tap()
        }
        XCTAssertTrue(select.waitForExistence(timeout: 8))
        select.tap()
        let choices = photos.images.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "照片,", "Photo,"))
        XCTAssertGreaterThanOrEqual(choices.count, 2)
        choices.element(boundBy: 0).tap()
        choices.element(boundBy: 1).tap()
        let share = photos.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Share", "分享", "共享")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 6))
        share.tap()
        let activity = photos.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 8))
        let moro = activity.descendants(matching: .any)["Moro"].firstMatch
        XCTAssertTrue(moro.waitForExistence(timeout: 8))
        moro.tap()
        expectation(for: NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue), evaluatedWith: app)
        waitForExpectations(timeout: 15)
        let attachments = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "compose.media.alt."))
        expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: attachments)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(app.textViews["compose.textInput"].value as? String, "")
        attach(app, "photos-two-images-new-editor")
        close(app, action: "Save Draft")
        waitForSummary(app, "Manual: 1; files: 0; uploads: 2; posts: 0")
    }

    private func launch(_ scenario: String = "normal") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SHARED_COMPOSE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_SHARE_SCENARIO": scenario]
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.buttons["shareFixture.stage"].waitForExistence(timeout: 8))
        return app
    }

    private func close(_ app: XCUIApplication, action: String) {
        app.navigationBars.buttons["Cancel"].tap()
        let button = app.alerts.buttons[action]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.composePostButton.waitForNonExistence(timeout: 8))
    }

    private func waitForSummary(_ app: XCUIApplication, _ value: String, editing: Bool = false) {
        let summary = app.staticTexts[editing ? "shareFixture.editorSummary" : "shareFixture.summary"]
        expectation(for: NSPredicate(format: "label == %@", value), evaluatedWith: summary)
        waitForExpectations(timeout: 15)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
