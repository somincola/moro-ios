import XCTest

final class DirectMessagesUITests: XCTestCase {
    @MainActor
    func testFirstMessagePreservesLinkAndOpensNativeDetail() {
        let app = launch()
        let conversation = app.buttons["directMessages.conversation.dm-alice"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 8))
        XCTAssertTrue(conversation.label.contains("remote.example/@author/123"))
        conversation.tap()
        let body = app.descendants(matching: .any)["conversation.body.dm-root"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue(body.label.contains("Second paragraph"))
        let card = app.descendants(matching: .any)["conversation.link.dm-root"].firstMatch
        XCTAssertTrue(card.isHittable)
        attach(app, name: "Direct message with a link")
        card.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Resolved remote article")).firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testKeyboardKeepsComposerVisibleAndCanSendFixtureReply() {
        let app = launch()
        openConversation(app)
        let input = app.descendants(matching: .any)["conversation.input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let send = app.buttons["conversation.send"]
        // Check the entire controls, including their lower edges, above the keyboard.
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(send.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        // XCTest excludes the QuickType row from the keyboard frame on iOS 26.
        // The screenshot also verifies the visible edge above that system row.
        XCTAssertTrue(input.isHittable)
        let singleLineHeight = input.frame.height
        input.typeText("A fixture reply")
        XCTAssertTrue(send.isEnabled)
        XCTAssertTrue(send.isHittable)
        attach(app, name: "Composer above keyboard")
        send.tap() // All requests are handled by DirectMessagesFixtureProtocol.
        let replyCard = app.descendants(matching: .any)["conversation.link.dm-sent"].firstMatch
        XCTAssertTrue(replyCard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["conversation.body.dm-sent"].firstMatch.exists)
        attach(app, name: "Outgoing link message")
        XCTAssertTrue(keyboard.exists)
        input.typeText(String(repeating: "A longer unsent draft. ", count: 12))
        XCTAssertGreaterThan(input.frame.height, singleLineHeight)
        XCTAssertLessThanOrEqual(input.frame.height, singleLineHeight * 4 + 1)
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 1)
        attach(app, name: "Multiline draft above keyboard")
    }

    @MainActor
    func testNewConversationSearchClearAndSelection() {
        let app = launch()
        let add = app.buttons["directMessages.newConversation"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let recent = app.buttons["newConversation.account.dm-alice"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attach(app, name: "New conversation")
        let search = app.textFields["newConversation.search"]
        search.tap()
        search.typeText("charlie")
        let result = app.buttons["newConversation.account.dm-charlie"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        app.buttons["newConversation.clear"].tap()
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.tap()
        XCTAssertTrue(app.descendants(matching: .any)["conversation.link.dm-root"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDarkLargeTextSheetAndComposer() {
        let app = launch(dark: true, large: true)
        let add = app.buttons["directMessages.newConversation"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let cancel = app.buttons["newConversation.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newConversation.account.dm-alice"].isHittable)
        XCTAssertGreaterThan(app.buttons["newConversation.account.dm-alice"].frame.height, 80)
        attach(app, name: "Large text new conversation")
        cancel.tap()
        openConversation(app)
        let input = app.descendants(matching: .any)["conversation.input"].firstMatch
        input.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(app.buttons["conversation.send"].frame.maxY, keyboard.frame.minY + 1)
        attach(app, name: "Large text dark composer")
    }

    @MainActor
    private func launch(dark: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DIRECT_MESSAGES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = dark ? "dark" : "light"
        if large {
            app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL"
            // Native sheet presentation also reads UIKit's content-size category.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch(isolatedFor: self)
        return app
    }

    @MainActor
    private func openConversation(_ app: XCUIApplication) {
        let conversation = app.buttons["directMessages.conversation.dm-alice"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 8))
        conversation.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
