import XCTest

@MainActor
final class ComposePublishingUITests: XCTestCase {
    func testLongPostClosesComposerAfterOneSubmitAndDisplaysItsBody() {
        let app = launch("success")
        defer { app.terminate() }
        publishButton(app).tap()
        assertPublished(app, requests: 1)
        attach(app, "long-post-published-once")
    }

    func testLostResponseShowsVisibleErrorAndRetryCreatesOnlyOnePost() {
        let app = launch("lost-response")
        defer { app.terminate() }
        publishButton(app).tap()
        let error = app.descendants(matching: .any)["compose.publishError"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.isHittable)
        XCTAssertTrue(error.label.contains("Could not confirm"))
        XCTAssertTrue(error.label.lowercased().contains("draft"))
        attach(app, "publish-error-above-keyboard")
        let post = publishButton(app)
        XCTAssertTrue(post.isEnabled)
        post.tap()
        assertPublished(app, requests: 2)
        attach(app, "lost-response-retry-single-post")
    }

    func testLongReplyAlsoClosesAfterOneSubmit() {
        let app = launch("slow-reply")
        defer { app.terminate() }
        publishButton(app).tap()
        assertPublishing(app)
        assertPublished(app, requests: 1)
    }

    func testSlowPostKeepsLoadingAndClosesWithoutASecondTap() {
        let app = launch("slow-post")
        defer { app.terminate() }
        publishButton(app).tap()
        assertPublishing(app)
        assertPublished(app, requests: 1)
    }

    func testImmediateResponseAlsoClosesItemPresentation() {
        let app = launch("immediate")
        defer { app.terminate() }
        publishButton(app).tap()
        assertPublished(app, requests: 1)
    }

    func testLoadingRemainsVisibleUntilSuccessfulPresentationCloses() {
        let app = launch("delayed-dismiss")
        defer { app.terminate() }
        publishButton(app).tap()
        XCTAssertTrue(app.staticTexts["publishFixture.dismissalRequested"].waitForExistence(timeout: 8))
        assertPublishing(app)
        attach(app, "successful-publish-awaiting-dismissal")
        assertPublished(app, requests: 1)
    }

    func testPostPublishRefreshDoesNotHoldComposerOpen() {
        let app = launch("slow-refresh")
        defer { app.terminate() }
        publishButton(app).tap()
        assertPublished(app, requests: 1)
        XCTAssertTrue(app.staticTexts["publishFixture.refresh"].exists)
        attach(app, "composer-closed-while-refresh-pending")
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PUBLISHING", "-moro.debug.logs", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_PUBLISH_SCENARIO": scenario]
        app.launch()
        let open = app.buttons["publishFixture.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let post = publishButton(app)
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: post)
        waitForExpectations(timeout: 10)
        return app
    }

    private func publishButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["compose.postButton"]
    }

    private func assertPublished(_ app: XCUIApplication, requests: Int) {
        // The presenting view can already contain the result while the cover animates out.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: publishButton(app))
        waitForExpectations(timeout: 12)
        let result = app.staticTexts["publishFixture.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertEqual(result.label, "Published posts: 1; requests: \(requests)")
        XCTAssertFalse(publishButton(app).exists)
        XCTAssertEqual(app.staticTexts["publishFixture.presentation"].label, "Presentation closed")
        // Post bodies render as SwiftUI Text (custom emoji inline), not a text view.
        let body = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Publish once")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        XCTAssertTrue(body.label.contains("文字应该立即出现"))
    }

    private func assertPublishing(_ app: XCUIApplication) {
        let post = publishButton(app)
        XCTAssertTrue(post.exists)
        XCTAssertFalse(post.isEnabled)
        // The toolbar puts the spoken status on its outer accessibility container;
        // inspect the actual activity indicator inside the native button.
        XCTAssertTrue(post.activityIndicators.firstMatch.exists)
        XCTAssertFalse(app.buttons["compose.editorOptions"].isEnabled)
        XCTAssertFalse(app.navigationBars.buttons["Cancel"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["compose.publishError"].firstMatch.exists)
        attach(app, "publishing-in-progress")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
