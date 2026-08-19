//
//  moroUITests.swift
//  moroUITests
//
//  Created by Noah on 11/24/25.
//

import XCTest

final class moroUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testNotificationRowsRouteToEffectiveStatusTargets() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["UITEST_NOTIFICATION_ROW_TAPS", "UITEST_DISABLE_ANIMATIONS"]
        app.launchEnvironment["UITEST_NOTIFICATION_ROW_TAPS"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()

        let result = app.staticTexts["notification.tapResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 12))
        XCTAssertEqual(result.label, "tap:none")

        let mainTap = app.buttons["notification.mainStatusTap"]
        XCTAssertTrue(mainTap.waitForExistence(timeout: 12))
        waitForElementToBeHittable(mainTap)
        mainTap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForResultLabel(result, equals: "tap:action-status")

        let quotedTap = app.buttons["notification.quotedStatusTap"]
        XCTAssertTrue(quotedTap.waitForExistence(timeout: 12))
        waitForElementToBeHittable(quotedTap)
        quotedTap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForResultLabel(result, equals: "tap:quoted-status")
    }

    @MainActor
    func testComposeCharacterCounterAndPostButton() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["UITEST_COMPOSE_COUNTER", "UITEST_DISABLE_ANIMATIONS"]
        app.launchEnvironment["UITEST_COMPOSE_COUNTER"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()

        let count = app.staticTexts["compose.charCount"]
        let post = app.buttons["compose.postButton"]
        XCTAssertTrue(
            count.waitForExistence(timeout: 12),
            "Compose counter harness should render its character count"
        )

        // Empty text -> 0 characters, posting disabled.
        XCTAssertEqual(count.label, "0")
        XCTAssertFalse(post.isEnabled)

        // A URL always counts as a fixed 23 characters.
        app.buttons["compose.set.url"].tap()
        waitForResultLabel(count, equals: "23")
        XCTAssertTrue(post.isEnabled)

        // A remote mention drops the @domain (@alice@mastodon.social -> @alice = 6).
        app.buttons["compose.set.mention"].tap()
        waitForResultLabel(count, equals: "6")
        XCTAssertTrue(post.isEnabled)

        // Over the 500-character limit -> posting disabled.
        app.buttons["compose.set.over"].tap()
        waitForResultLabel(count, equals: "501")
        XCTAssertFalse(post.isEnabled)

        // Cleared -> 0, disabled again.
        app.buttons["compose.set.clear"].tap()
        waitForResultLabel(count, equals: "0")
        XCTAssertFalse(post.isEnabled)
    }

    @MainActor
    func testComposeMediaDeletionKeepsEveryRemainingAttachmentActionable() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["UITEST_COMPOSE_MEDIA"]
        app.launchEnvironment["UITEST_COMPOSE_MEDIA"] = "1"
        app.launch()

        let ids = app.staticTexts["compose.media.ids"]
        XCTAssertTrue(ids.waitForExistence(timeout: 12))
        XCTAssertEqual(ids.label, "media-1,media-2,media-3,media-4")

        let deletionSequence: [(id: String, remaining: String)] = [
            ("media-2", "media-1,media-3,media-4"),
            ("media-4", "media-1,media-3"),
            ("media-1", "media-3"),
            ("media-3", ""),
        ]

        for step in deletionSequence {
            let removeButton = app.buttons["compose.media.remove.\(step.id)"]
            XCTAssertTrue(removeButton.waitForExistence(timeout: 8))
            waitForElementToBeHittable(removeButton)
            removeButton.tap()
            waitForResultLabel(ids, equals: step.remaining)
        }

        app.buttons["compose.media.reset"].tap()
        waitForResultLabel(ids, equals: "media-1,media-2,media-3,media-4")

        let firstRemainingButton = app.buttons["compose.media.remove.media-1"]
        XCTAssertTrue(firstRemainingButton.waitForExistence(timeout: 8))
        firstRemainingButton.tap()
        waitForResultLabel(ids, equals: "media-2,media-3,media-4")
    }

    @MainActor
    func testAccountDeletionEntryIsVisibleAtBottomAndDirect() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["UITEST_ACCOUNT_DELETION", "UITEST_DISABLE_ANIMATIONS"]
        app.launchEnvironment["UITEST_ACCOUNT_DELETION"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()

        let deletionEntry = app.buttons["accountManagement.serverAccountSettings"]
        XCTAssertTrue(
            deletionEntry.waitForExistence(timeout: 12),
            "The direct server deletion entry should stay visible without a swipe or menu"
        )
        XCTAssertTrue(deletionEntry.isHittable)
        XCTAssertEqual(deletionEntry.label, "Delete Account on Server")
        XCTAssertGreaterThan(
            deletionEntry.frame.midY,
            app.windows.firstMatch.frame.height * 0.75,
            "The lightweight deletion entry should remain anchored near the bottom"
        )
    }

    @MainActor
    func testSettingsUsesBottomSheetPresentation() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["UITEST_SETTINGS_SHEET", "UITEST_DISABLE_ANIMATIONS"]
        app.launchEnvironment["UITEST_SETTINGS_SHEET"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()

        let settingsNavigationBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavigationBar.waitForExistence(timeout: 12))
        XCTAssertFalse(
            app.buttons["settings.sheet.close"].exists,
            "The large Settings sheet should rely on its grabber instead of a duplicate close button"
        )

        let window = app.windows.firstMatch
        XCTAssertLessThan(
            settingsNavigationBar.frame.minY,
            window.frame.height * 0.16,
            "Settings should open at the large sheet detent"
        )

        let grabberY = max(
            0.02,
            (settingsNavigationBar.frame.minY - 12) / window.frame.height
        )
        let grabber = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: grabberY)
        )
        let dismissTarget = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)
        )
        grabber.press(forDuration: 0.1, thenDragTo: dismissTarget)

        XCTAssertTrue(
            settingsNavigationBar.waitForNonExistence(timeout: 8),
            "The Settings sheet should remain dismissible by dragging its grabber"
        )
    }

    @MainActor
    func testAuthenticatedProductionLayoutContracts() throws {
        let app = XCUIApplication()
        defer { app.terminate() }

        let configurations = [
            ProductionLayoutConfiguration(
                name: "light-default",
                colorScheme: "light",
                dynamicTypeSize: nil
            ),
            ProductionLayoutConfiguration(
                name: "dark-default",
                colorScheme: "dark",
                dynamicTypeSize: nil
            ),
            ProductionLayoutConfiguration(
                name: "light-accessibility-xxxl",
                colorScheme: "light",
                dynamicTypeSize: "accessibilityXXXL"
            ),
            ProductionLayoutConfiguration(
                name: "dark-accessibility-xxxl",
                colorScheme: "dark",
                dynamicTypeSize: "accessibilityXXXL"
            ),
        ]

        for configuration in configurations {
            app.terminate()
            app.launchArguments = ["UITEST_USE_FULL_APP", "UITEST_DISABLE_ANIMATIONS"]
            app.launchEnvironment = [
                "UITEST_USE_FULL_APP": "1",
                "UITEST_DISABLE_ANIMATIONS": "1",
                "UITEST_COLOR_SCHEME": configuration.colorScheme,
            ]
            if let dynamicTypeSize = configuration.dynamicTypeSize {
                app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = dynamicTypeSize
            }
            app.launch()

            try assertProductionLayoutContracts(
                app: app,
                configurationName: configuration.name
            )
        }
    }

    @MainActor
    func testAuthenticatedComposePrimaryControlsAreDirectAndSchedulingIsHidden() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["UITEST_USE_FULL_APP", "UITEST_DISABLE_ANIMATIONS"]
        app.launchEnvironment = [
            "UITEST_USE_FULL_APP": "1",
            "UITEST_DISABLE_ANIMATIONS": "1",
        ]
        app.launch()

        let composeButton = app.buttons["home.composeButton"]
        guard composeButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Authenticated compose baseline requires a signed-in simulator")
        }
        composeButton.tap()

        let audienceMenu = app.buttons["compose.audienceMenu"]
        let mediaMenu = app.buttons["compose.mediaMenu"]
        let emojiToggle = app.buttons["compose.emojiToggle"]
        let warningToggle = app.buttons["compose.contentWarningToggle"]
        let pollToggle = app.buttons["compose.pollToggle"]
        let languageMenu = app.buttons["compose.languageMenu"]
        let draftsItem = app.buttons["compose.destination.drafts"]
        XCTAssertTrue(audienceMenu.waitForExistence(timeout: 10))

        let orderedToolbarItems = [
            mediaMenu,
            emojiToggle,
            warningToggle,
            pollToggle,
            draftsItem,
            languageMenu,
        ]
        for item in orderedToolbarItems {
            XCTAssertTrue(item.waitForExistence(timeout: 10))
        }
        for (leadingItem, trailingItem) in zip(
            orderedToolbarItems,
            orderedToolbarItems.dropFirst()
        ) {
            XCTAssertLessThan(
                leadingItem.frame.midX,
                trailingItem.frame.midX,
                "Expected \(leadingItem.identifier) before \(trailingItem.identifier)"
            )
        }

        XCTAssertFalse(app.buttons["compose.moreMenu"].exists)
        XCTAssertFalse(app.buttons["compose.destination.schedule"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["compose.scheduleSheet"].firstMatch.exists)
        addScreenshot(named: "compose-direct-controls", app: app)

        draftsItem.tap()
        let draftsSheet = app.descendants(matching: .any)["compose.draftsSheet"].firstMatch
        XCTAssertTrue(draftsSheet.waitForExistence(timeout: 8))
        addScreenshot(named: "compose-direct-drafts", app: app)
    }

    @MainActor
    func testAuthenticatedComposerCaretSurvivesInputSourceSwitch() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["UITEST_USE_FULL_APP", "UITEST_DISABLE_ANIMATIONS"]
        app.launchEnvironment = [
            "UITEST_USE_FULL_APP": "1",
            "UITEST_DISABLE_ANIMATIONS": "1",
        ]
        app.launch()

        let composeButton = app.buttons["home.composeButton"]
        guard composeButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Authenticated compose baseline requires a signed-in simulator")
        }
        composeButton.tap()

        let editor = app.textViews["compose.textInput"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        addScreenshot(named: "compose-placeholder-caret-alignment", app: app)
        editor.typeText("1111 2222")

        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.10)).tap()

        let emojiToggle = app.buttons["compose.emojiToggle"]
        XCTAssertTrue(emojiToggle.waitForExistence(timeout: 5))
        emojiToggle.tap()

        let emojiPicker = app.descendants(matching: .any)["compose.emojiPicker"].firstMatch
        XCTAssertTrue(
            emojiPicker.waitForExistence(timeout: 5),
            "The custom emoji input should appear without resigning the composer"
        )

        emojiToggle.tap()
        XCTAssertTrue(
            emojiPicker.waitForNonExistence(timeout: 5),
            "Returning to the system keyboard should keep the same text view active"
        )

        editor.typeText("X")
        let updatedText = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(updatedText.contains("X"))
        XCTAssertFalse(
            updatedText.hasSuffix("X"),
            "Typing after the input-source round trip should use the tapped caret instead of the old end position"
        )
    }

    @MainActor
    func testAuthenticatedComposerContentWarningUsesCompactWarningField() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["UITEST_USE_FULL_APP", "UITEST_DISABLE_ANIMATIONS"]
        app.launchEnvironment = [
            "UITEST_USE_FULL_APP": "1",
            "UITEST_DISABLE_ANIMATIONS": "1",
        ]
        app.launch()

        let composeButton = app.buttons["home.composeButton"]
        guard composeButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Authenticated compose baseline requires a signed-in simulator")
        }
        composeButton.tap()

        let warningToggle = app.buttons["compose.contentWarningToggle"]
        XCTAssertTrue(warningToggle.waitForExistence(timeout: 10))
        warningToggle.tap()

        let warningInput = app.descendants(matching: .any)["compose.contentWarningInput"].firstMatch
        XCTAssertTrue(warningInput.waitForExistence(timeout: 5))
        XCTAssertTrue(warningInput.isHittable)
        warningInput.tap()
        warningInput.typeText("Spoilers ahead")

        XCTAssertLessThanOrEqual(
            warningInput.frame.height,
            72,
            "A short warning title should remain a compact input above the post body"
        )
        addScreenshot(named: "compose-content-warning-field", app: app)
    }

    private struct ProductionLayoutConfiguration {
        let name: String
        let colorScheme: String
        let dynamicTypeSize: String?
    }

    @MainActor
    private func assertProductionLayoutContracts(
        app: XCUIApplication,
        configurationName: String
    ) throws {
        let composeButton = app.buttons["home.composeButton"]
        guard composeButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Authenticated production UI baseline requires a signed-in simulator")
        }

        let window = app.windows.firstMatch
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(composeButton.frame.width, 64)
        XCTAssertLessThanOrEqual(composeButton.frame.height, 64)
        XCTAssertLessThan(abs(composeButton.frame.width - composeButton.frame.height), 2)
        XCTAssertGreaterThan(composeButton.frame.minY, window.frame.height * 0.65)
        XCTAssertLessThanOrEqual(
            composeButton.frame.maxY,
            tabBar.frame.minY - 4,
            "The compose control must remain a local overlay above the system tab bar"
        )

        let visibleTimelineRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "timeline.status.")
        )
        guard visibleTimelineRows.firstMatch.waitForExistence(timeout: 15) else {
            throw XCTSkip("Production timeline baseline requires at least one loaded status")
        }
        XCTAssertTrue(
            visibleTimelineRows.allElementsBoundByIndex.contains { row in
                row.frame.maxY > composeButton.frame.minY
                    && row.frame.minY < tabBar.frame.minY
            },
            "Timeline content must extend behind the local compose overlay instead of ending in an opaque footer"
        )
        addScreenshot(named: "production-home-layout-\(configurationName)", app: app)

        let meTab = app.tabBars.buttons["mainTab.me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 8))
        meTab.tap()

        // SwiftUI propagates a container accessibility identifier to its image child.
        // Query the structural container so frame assertions remain unambiguous.
        let profileHeader = app.otherElements["profile.header"].firstMatch
        let moreButton = app.buttons["profile.moreButton"]
        XCTAssertTrue(profileHeader.waitForExistence(timeout: 12))
        XCTAssertTrue(moreButton.waitForExistence(timeout: 12))
        addScreenshot(named: "production-profile-layout-\(configurationName)", app: app)
        XCTAssertGreaterThan(profileHeader.frame.width, window.frame.width * 0.9)
        XCTAssertGreaterThan(profileHeader.frame.height, 150)
        XCTAssertLessThanOrEqual(moreButton.frame.width, 64)
        XCTAssertLessThanOrEqual(moreButton.frame.height, 64)
        // XCUI reports the semantic hit target, which includes up to 4 pt of
        // vertical padding around the visually circular glass surface.
        XCTAssertLessThanOrEqual(abs(moreButton.frame.width - moreButton.frame.height), 10)
        XCTAssertTrue(
            profileHeader.frame.intersects(moreButton.frame),
            "The local profile action should overlay the immersive header"
        )
        XCTAssertLessThanOrEqual(
            moreButton.frame.width * moreButton.frame.height,
            profileHeader.frame.width * profileHeader.frame.height * 0.12,
            "The profile action must remain local instead of becoming a full-width surface"
        )
    }

    private func waitForResultLabel(_ element: XCUIElement, equals expected: String) {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        XCTAssertEqual(result, .completed, "Expected label \(expected), got \(element.label)")
    }

    private func waitForElementToBeHittable(_ element: XCUIElement) {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        XCTAssertEqual(result, .completed, "Element should be hittable before tap")
    }

    private func addScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
