import XCTest

@MainActor
final class ProfileExperienceUITests: XCTestCase {
    private let rawLink = "https://example.com/a/long/path?first=1&second=2"

    func testRenamingFieldPreservesExistingValueAboveLoweredLimit() {
        let app = launch(extra: ["UITEST_PROFILE_LOWER_FIELD_LIMIT": "1"])
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.fields"].tap()
        let first = app.buttons["profile.field.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        let name = app.textFields["profile.field.name"]
        let value = app.textFields["profile.field.value"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, rawLink)
        name.tap()
        name.typeText("Link ")
        let editedName = (name.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(editedName.contains("Link"))
        let done = app.buttons["profile.field.done"]
        guard done.isEnabled else {
            XCTFail("An untouched existing value must not block renaming the field")
            return
        }
        done.tap()
        app.buttons["profile.fields.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.fields"].waitForExistence(timeout: 8))
        app.buttons["profile.edit.fields"].tap()
        waitLabel(first, contains: editedName)
        first.tap()
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, rawLink)
        // Once the value itself is edited, the current server limit applies.
        value.tap()
        value.typeText("x")
        XCTAssertFalse(done.isEnabled)
    }

    func testFieldDragOrderAndRawLinkSurviveSaving() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.fields"].tap()
        let first = app.buttons["profile.field.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(first.label.contains(rawLink))
        app.buttons["profile.fields.reorder"].tap()
        let firstCell = app.cells.containing(.any, identifier: "profile.field.0").firstMatch
        let handle = firstCell.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder")).firstMatch
        let last = app.descendants(matching: .any).matching(identifier: "profile.field.2").firstMatch
        XCTAssertTrue(handle.exists)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: last.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.95)))
        waitLabel(last, contains: "Website")
        app.buttons["profile.fields.reorder"].tap()
        XCTAssertTrue(app.buttons["profile.field.2"].isHittable)
        app.buttons["profile.fields.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.fields"].waitForExistence(timeout: 8))
        app.buttons["profile.edit.fields"].tap()
        waitLabel(last, contains: "Website")
        XCTAssertTrue(last.label.contains(rawLink))
        last.tap()
        let value = app.textFields["profile.field.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, rawLink)
        let name = app.textFields["profile.field.name"]
        name.tap()
        name.typeText("Link ")
        // A multiline field places the caret at the tapped position. Verify the
        // actual edited draft instead of assuming it always appends at the end.
        let editedName = (name.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(editedName, "Website")
        XCTAssertTrue(editedName.contains("Link"))
        app.buttons["profile.field.done"].tap()
        waitLabel(last, contains: editedName)
        app.buttons["profile.fields.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.fields"].waitForExistence(timeout: 8))
        app.buttons["profile.edit.fields"].tap()
        waitLabel(last, contains: editedName)
        XCTAssertTrue(last.label.contains(rawLink))
        attach(app, "profile-fields-reordered")
    }

    func testFieldRowWhitespaceOpensEditorAndDeletionCanBeDiscarded() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.fields"].tap()
        let first = app.buttons["profile.field.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        // The empty trailing area must be as tappable as the field text.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
        let value = app.textFields["profile.field.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, rawLink)
        let delete = app.buttons["profile.field.delete"]
        reveal(delete, in: app)
        delete.tap()
        waitLabel(first, contains: "About")
        XCTAssertTrue(app.buttons["profile.fields.save"].isEnabled)
        app.buttons["profile.editor.back"].tap()
        let discard = app.buttons["profile.editor.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        XCTAssertTrue(app.buttons["profile.edit.fields"].waitForExistence(timeout: 5))
        app.buttons["profile.edit.fields"].tap()
        waitLabel(first, contains: "Website")
        XCTAssertTrue(first.label.contains(rawLink))
        XCTAssertTrue(app.buttons["profile.field.2"].exists)
    }

    func testSwipeDeletingAFieldPersistsAndPreservesOtherValues() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.fields"].tap()
        let middle = app.buttons["profile.field.1"]
        XCTAssertTrue(middle.waitForExistence(timeout: 8))
        middle.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        waitLabel(middle, contains: "Garden")
        XCTAssertFalse(app.buttons["profile.field.2"].exists)
        app.buttons["profile.fields.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.fields"].waitForExistence(timeout: 8))
        app.buttons["profile.edit.fields"].tap()
        waitLabel(middle, contains: "Garden")
        XCTAssertTrue(app.buttons["profile.field.0"].label.contains(rawLink))
        XCTAssertFalse(app.buttons["profile.field.2"].exists)
    }

    func testAddingFieldsUsesFreshDraftsAndPersistsThroughNativeNavigation() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.fields"].tap()
        let add = app.buttons["profile.field.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        let name = app.textFields["profile.field.name"]
        let value = app.textFields["profile.field.value"]
        let last = app.buttons["profile.field.3"]

        for title in ["Temporary", "Docs"] {
            add.tap()
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["profile.field.done"].isEnabled)
            XCTAssertFalse(app.buttons["profile.field.delete"].exists)
            name.tap()
            name.typeText(title)
            value.tap()
            value.typeText("https://example.com/docs")
            app.buttons["profile.field.done"].tap()
            waitLabel(last, contains: title)

            if title == "Temporary" {
                last.tap()
                XCTAssertTrue(name.waitForExistence(timeout: 5))
                XCTAssertEqual(name.value as? String, title)
                app.buttons["profile.field.delete"].tap()
                XCTAssertTrue(add.waitForExistence(timeout: 5))
            }
        }
        app.buttons["profile.fields.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.fields"].waitForExistence(timeout: 8))
        app.buttons["profile.edit.fields"].tap()
        waitLabel(last, contains: "Docs")
        XCTAssertTrue(last.label.contains("https://example.com/docs"))
        XCTAssertFalse(last.label.contains("Temporary"))
        XCTAssertTrue(app.buttons["profile.field.0"].label.contains(rawLink))
    }

    func testDiscardingFieldDraftLeavesStoredValueUnchanged() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.fields"].tap()
        let first = app.buttons["profile.field.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        let name = app.textFields["profile.field.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" changed")
        app.buttons["profile.editor.back"].tap()
        let discard = app.buttons["profile.editor.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(first.label.contains("changed"))
        XCTAssertFalse(app.buttons["profile.fields.save"].isEnabled)
    }

    func testBasicNameSavePreservesRawBiography() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.basic"].tap()
        let name = app.textFields["profile.basic.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        let bio = app.textViews["profile.basic.bio"]
        XCTAssertTrue((bio.value as? String)?.contains(rawLink) == true)
        name.tap()
        name.typeText(" Updated")
        app.buttons["profile.basic.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.basic"].waitForExistence(timeout: 8))
        app.buttons["profile.edit.basic"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Moro Tester Updated")
        XCTAssertTrue((bio.value as? String)?.contains(rawLink) == true)
    }

    func testFeaturedTagSuggestionsAddAndDeletePersist() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.featuredTags"].tap()
        let suggestion = app.buttons["#swift"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
        suggestion.tap()
        let remove = app.buttons["profile.featuredTags.remove.swift"]
        reveal(remove, in: app)
        XCTAssertTrue(remove.exists)
        back(app)
        app.buttons["profile.edit.featuredTags"].tap()
        reveal(remove, in: app)
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        back(app)
        app.buttons["profile.edit.featuredTags"].tap()
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
        XCTAssertFalse(remove.exists)
    }

    func testFailedTagDeletionKeepsTheTagVisible() {
        let app = launch(extra: ["UITEST_PROFILE_DELETE_FAILS": "1"])
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.featuredTags"].tap()
        let remove = app.buttons["profile.featuredTags.remove.app"]
        reveal(remove, in: app)
        remove.tap()
        XCTAssertTrue(app.staticTexts["profile.featuredTags.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(remove.exists)
    }

    func testDisplaySwitchesAndFeaturedTagFilterRoundTrip() {
        let app = launch()
        defer { app.terminate() }
        let appTag = app.buttons["profile.featuredTag.app"].firstMatch
        reveal(appTag, in: app)
        appTag.tap()
        XCTAssertTrue(appTag.isSelected)
        let pinned = app.staticTexts["Pinned app post"].firstMatch
        reveal(pinned, in: app)
        XCTAssertTrue(pinned.exists)
        XCTAssertFalse(app.staticTexts["Daily garden post"].exists)
        pinned.tap()
        back(app)
        XCTAssertTrue(appTag.waitForExistence(timeout: 5))
        XCTAssertTrue(appTag.isSelected)
        appTag.tap()
        XCTAssertFalse(appTag.isSelected)
        for _ in 0..<3 { app.swipeDown() }
        openOverview(app)
        app.buttons["profile.edit.display"].tap()
        let local = app.switches["profile.display.featuredTags"]
        XCTAssertTrue(local.waitForExistence(timeout: 8))
        local.tap()
        XCTAssertTrue(["0", "Off"].contains(local.value as? String ?? ""))
        let media = app.switches["profile.display.media"]
        XCTAssertTrue(media.waitForExistence(timeout: 5))
        media.tap()
        XCTAssertTrue(["0", "Off"].contains(media.value as? String ?? ""))
        app.buttons["profile.display.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.display"].waitForExistence(timeout: 8))
        back(app)
        XCTAssertTrue(app.buttons["profile.moreButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(appTag.exists)
        XCTAssertFalse(app.buttons["profile.tab.media"].exists)
        openOverview(app)
        app.buttons["profile.edit.display"].tap()
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        XCTAssertTrue(["0", "Off"].contains(local.value as? String ?? ""))
        local.tap()
        app.buttons["profile.display.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.display"].waitForExistence(timeout: 5))
        back(app)
        reveal(appTag, in: app)
        XCTAssertTrue(appTag.exists)
    }

    func testEmptyOrDisabledFeaturedTagsDoNotShowFilterBar() {
        for environment in [["UITEST_PROFILE_EMPTY_TAGS": "1"], ["UITEST_PROFILE_TAGS_DISABLED": "1"]] {
            let app = launch(extra: environment)
            XCTAssertTrue(app.buttons["profile.tab.posts"].waitForExistence(timeout: 8))
            app.swipeUp()
            XCTAssertFalse(app.buttons["profile.featuredTag.app"].exists)
            XCTAssertFalse(app.scrollViews["profile.featuredTags.filters"].exists)
            app.terminate()
        }
    }

    func testOlderServerKeepsUnsupportedControlsDisabled() {
        let app = launch(extra: ["UITEST_PROFILE_LEGACY": "1"])
        defer { app.terminate() }
        openOverview(app)
        app.buttons["profile.edit.display"].tap()
        let media = app.switches["profile.display.media"]
        XCTAssertTrue(media.waitForExistence(timeout: 8))
        XCTAssertFalse(media.isEnabled)
        XCTAssertTrue(app.switches["profile.display.featuredTags"].isEnabled)
        XCTAssertTrue(app.switches["profile.display.connections"].isEnabled)
    }

    func testRepliesContinuePastAFullPageWithoutReplies() {
        let app = launch()
        defer { app.terminate() }
        let replies = app.buttons["profile.tab.replies"].firstMatch
        reveal(replies, in: app)
        replies.tap()
        let reply = app.staticTexts["Reply from the second page"].firstMatch
        reveal(reply, in: app)
        XCTAssertTrue(reply.exists)
    }

    func testReplyScanningOffersManualContinuationAfterThreeEmptyPages() {
        let app = launch(extra: ["UITEST_PROFILE_NO_REPLIES": "1"])
        defer { app.terminate() }
        let replies = app.buttons["profile.tab.replies"].firstMatch
        reveal(replies, in: app)
        replies.tap()
        let more = app.buttons["profile.loadMoreEmptyPage"]
        reveal(more, in: app)
        XCTAssertTrue(more.exists)
        more.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
    }

    func testEditorLayoutInLightAndDarkAtDefaultAndAccessibilitySizes() {
        for scheme in ["light", "dark"] {
            for large in [false, true] {
                let app = launch(extra: large ? ["UITEST_DYNAMIC_TYPE_SIZE": "accessibilityXXXL"] : [:], scheme: scheme)
                let suffix = "\(scheme)-\(large ? "accessibilityXXXL" : "default")"
                openOverview(app)
                attach(app, "profile-overview-\(suffix)")
                for destination in ["basic", "fields", "featuredTags", "display"] {
                    let link = app.buttons["profile.edit.\(destination)"]
                    reveal(link, in: app)
                    link.tap()
                    let target: XCUIElement
                    switch destination {
                    case "fields": target = app.buttons["profile.field.0"]
                    case "featuredTags": target = app.textFields["profile.featuredTags.input"]
                    case "display": target = app.switches["profile.display.featuredTags"]
                    default: target = app.textFields["profile.basic.name"]
                    }
                    reveal(target, in: app)
                    XCTAssertTrue(target.exists)
                    XCTAssertGreaterThanOrEqual(target.frame.minX, 0)
                    XCTAssertLessThanOrEqual(target.frame.maxX, app.windows.firstMatch.frame.maxX)
                    attach(app, "profile-\(destination)-\(suffix)")
                    if destination == "fields" {
                        target.tap()
                        let value = app.textFields["profile.field.value"]
                        reveal(value, in: app)
                        XCTAssertGreaterThan(value.frame.width, app.windows.firstMatch.frame.width * 0.65)
                        let done = app.buttons["profile.field.done"]
                        XCTAssertTrue(done.isHittable)
                        attach(app, "profile-field-detail-\(suffix)")
                        back(app)
                    }
                    back(app)
                }
                app.terminate()
            }
        }
    }

    private func launch(extra: [String: String] = [:], scheme: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PROFILE_EXPERIENCE", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_COLOR_SCHEME": scheme, "UITEST_DISABLE_ANIMATIONS": "1"]
        app.launchEnvironment.merge(extra) { _, new in new }
        app.launch()
        XCTAssertTrue(app.buttons["profile.moreButton"].waitForExistence(timeout: 10))
        return app
    }

    private func openOverview(_ app: XCUIApplication) {
        app.buttons["profile.moreButton"].tap()
        let edit = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Edit profile")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.buttons["profile.edit.basic"].waitForExistence(timeout: 5))
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    private func waitLabel(_ element: XCUIElement, contains text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
