import UIKit
import XCTest

@MainActor
final class ProfileExperienceUITests: XCTestCase {
    private let rawLink = "https://example.com/a/long/path?first=1&second=2"

    func testHiddenConnectionsRemainAccessibleToTheAccountOwner() {
        let app = launch(extra: ["UITEST_PROFILE_HIDE_COLLECTIONS": "1"])
        defer { app.terminate() }
        for (kind, title) in [("following", "Following"), ("followers", "Followers")] {
            let stat = app.buttons["profile.stat.\(kind)"]
            reveal(stat, in: app)
            XCTAssertNotEqual(stat.value as? String, "List hidden")
            stat.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Connection Tester"].waitForExistence(timeout: 5))
            attach(app, "profile-owner-hidden-\(kind)")
            back(app)
        }
    }

    func testHiddenConnectionsStayPrivateToOtherViewers() {
        let app = launch(extra: ["UITEST_PROFILE_HIDE_COLLECTIONS": "1", "UITEST_OTHER_PROFILE": "1"])
        defer { app.terminate() }
        for (kind, title) in [("following", "Following"), ("followers", "Followers")] {
            let stat = app.buttons["profile.stat.\(kind)"]
            reveal(stat, in: app)
            XCTAssertEqual(stat.value as? String, "List hidden")
            stat.tap()
            XCTAssertTrue(app.buttons["profile.moreButton"].isHittable)
            XCTAssertFalse(app.navigationBars[title].exists)
            XCTAssertFalse(app.staticTexts["Connection Tester"].exists)
        }
        attach(app, "profile-visitor-hidden-connections")
    }

    func testFollowStateWaitsForTheServerAndBellShowsSubscriptionState() {
        for scheme in ["light", "dark"] {
            let app = launch(extra: ["UITEST_OTHER_PROFILE": "1", "UITEST_PROFILE_RELATIONSHIP": "following",
                                     "UITEST_PROFILE_RELATIONSHIP_DELAY": "8"], scheme: scheme, animations: true)
            // Unknown state is a neutral capsule, never a guessed "Follow".
            let placeholder = app.descendants(matching: .any)["profile.follow.placeholder"]
            XCTAssertTrue(placeholder.waitForExistence(timeout: 3))
            XCTAssertEqual(placeholder.label, "Checking follow status")
            XCTAssertFalse(app.buttons["profile.follow"].exists)
            attach(app, "profile-follow-checking-\(scheme)")

            let follow = app.buttons["profile.follow"]
            XCTAssertTrue(follow.waitForExistence(timeout: 12))
            XCTAssertEqual(follow.label, "Following")
            XCTAssertFalse(placeholder.exists)

            let bell = app.buttons["profile.notificationToggle"]
            XCTAssertTrue(bell.waitForExistence(timeout: 3))
            XCTAssertEqual(bell.label, "Turn on post notifications")
            attach(app, "profile-bell-off-\(scheme)")
            bell.tap()
            waitLabel(bell, contains: "Turn off")
            Thread.sleep(forTimeInterval: 1.2)  // let the replace + wiggle finish for the screenshot
            attach(app, "profile-bell-on-\(scheme)")
            app.terminate()
        }
    }

    func testCompactProfileInfoInLightAndDarkAtDefaultAndAccessibilitySizes() {
        for scheme in ["light", "dark"] {
            for large in [false, true] {
                var environment = ["UITEST_PROFILE_COMPACT_INFO": "1"]
                if large { environment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL" }
                let app = launch(extra: environment, scheme: scheme)
                let bio = app.descendants(matching: .any).matching(identifier: "profile.bio").firstMatch
                XCTAssertTrue(bio.waitForExistence(timeout: 8))
                XCTAssertTrue((bio.value as? String ?? "").contains("Happy to be here—nice to meet you all! 👋"))
                XCTAssertEqual(bio.frame.minX, 16, accuracy: 1)
                XCTAssertEqual(bio.frame.maxX, app.frame.width - 16, accuracy: 1)
                if large {
                    XCTAssertGreaterThan(bio.frame.height, 200)
                    for _ in 0..<6 {
                        if bio.frame.minY < 180 { break }
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                            .press(forDuration: 0.1,
                                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                                withVelocity: .slow, thenHoldForDuration: 0.2)
                    }
                    XCTAssertLessThan(bio.frame.minY, 180, "Long bio must scroll with the profile")
                } else {
                    XCTAssertLessThan(bio.frame.height, 135, "Bio must not use full blank lines between paragraphs")
                }
                let suffix = "\(scheme)-\(large ? "accessibilityXXXL" : "default")"
                attach(app, "profile-compact-info-\(suffix)")
                let posts = app.buttons["profile.tab.posts"].firstMatch
                if large {
                    let blog = app.staticTexts["somlar.com"].firstMatch
                    for _ in 0..<10 {
                        if blog.frame.maxY < posts.frame.minY - 24 { break }
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                            .press(forDuration: 0.1,
                                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                                withVelocity: .slow, thenHoldForDuration: 0.2)
                    }
                    XCTAssertTrue(blog.isHittable, "Fields below a long bio must remain reachable")
                    XCTAssertGreaterThan(blog.frame.minY, app.navigationBars.firstMatch.frame.maxY)
                    XCTAssertLessThan(blog.frame.maxY, posts.frame.minY - 24,
                        "The last field must not be hidden behind docked tabs")
                    attach(app, "profile-compact-fields-\(suffix)")
                }
                reveal(posts, in: app)
                XCTAssertTrue(posts.isHittable)
                app.terminate()
            }
        }
    }

    func testProfileChromeMatchesNativeNavigationBarAfterScrollingAndReturning() {
        let app = launch(animations: true)
        defer { app.terminate() }
        scrollToCollapsedHeader(app)
        attach(app, "profile-header-partially-scrolled-light")
        assertNavigationBackgroundIsOpaque(app)
        assertTabsMeetNavigationBar(app)
        attach(app, "profile-header-pinned-light")

        openOverview(app)
        back(app)
        XCTAssertTrue(app.buttons["profile.moreButton"].waitForExistence(timeout: 5))
        assertTabsMeetNavigationBar(app)
        attach(app, "profile-header-after-return")
    }

    func testProfileChromeMatchesNativeNavigationBarInDarkMode() {
        let app = launch(scheme: "dark", animations: true)
        defer { app.terminate() }
        scrollToCollapsedHeader(app)
        attach(app, "profile-header-partially-scrolled-dark")
        assertNavigationBackgroundIsOpaque(app)
        assertTabsMeetNavigationBar(app)
        attach(app, "profile-header-pinned-dark")
    }

    private func scrollToCollapsedHeader(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.39)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.navigationBars.staticTexts["Moro Tester"].waitForExistence(timeout: 5))
    }

    private func assertTabsMeetNavigationBar(_ app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 { app.swipeUp() }
        let posts = app.buttons["profile.tab.posts"].firstMatch
        XCTAssertTrue(posts.waitForExistence(timeout: 5), file: file, line: line)
        let navigationBar = app.navigationBars.firstMatch
        // Accessibility exposes the title bounds, below 12 pt section padding
        // and 10 pt button padding. Compare the actual section edge to UIKit.
        let sectionTop = posts.frame.minY - 22
        XCTAssertEqual(sectionTop, navigationBar.frame.maxY, accuracy: 1,
            "Pinned tabs must meet the native navigation bar without overlap or a gap.", file: file, line: line)
        XCTAssertTrue(app.buttons["profile.moreButton"].isHittable, file: file, line: line)
    }

    private func assertNavigationBackgroundIsOpaque(_ app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars.firstMatch.frame
        guard let image = app.screenshot().image.cgImage,
            let data = image.dataProvider?.data, let pixels = CFDataGetBytePtr(data) else {
            XCTFail("Unable to inspect the navigation bar screenshot", file: file, line: line)
            return
        }
        let scale = CGFloat(image.width) / app.frame.width
        let channels = image.bitsPerPixel / 8
        let referenceY = Int((bar.minY + 2) * scale)
        let bottomY = Int((bar.maxY - 3) * scale)
        var largestDifference = 0
        // Both rows are clear of the title and trailing button. A transparent
        // strip exposes the scrolling username or its blur in the bottom row.
        for x in Int(16 * scale)..<Int(app.frame.width * 0.6 * scale) {
            for channel in 0..<channels {
                let reference = Int(pixels[referenceY * image.bytesPerRow + x * channels + channel])
                let bottom = Int(pixels[bottomY * image.bytesPerRow + x * channels + channel])
                largestDifference = max(largestDifference, abs(reference - bottom))
            }
        }
        XCTAssertLessThanOrEqual(largestDifference, 6,
            "The native navigation bar must remain opaque to its bottom edge.", file: file, line: line)
    }

    func testRenamingFieldPreservesExistingValueAboveLoweredLimit() {
        let app = launch(extra: ["UITEST_PROFILE_LOWER_FIELD_LIMIT": "1"])
        defer { app.terminate() }
        openOverview(app)
        let name = input(app, "profile.field.0.name")
        reveal(name, in: app)
        XCTAssertEqual(input(app, "profile.field.0.value").value as? String, rawLink)
        name.tap()
        name.typeText(" Link")
        // An untouched existing value above the lowered limit must not block saving.
        XCTAssertFalse(app.staticTexts[limitsExceeded].exists)
        save(app)
        openOverview(app)
        reveal(name, in: app)
        XCTAssertEqual(name.value as? String, "Website Link")
        let value = input(app, "profile.field.0.value")
        XCTAssertEqual(value.value as? String, rawLink)
        // Once the value itself is edited, the current server limit applies.
        value.tap()
        value.typeText("x")
        XCTAssertTrue(app.staticTexts[limitsExceeded].waitForExistence(timeout: 3))
    }

    func testFieldsEditInPlaceAndSaveInTheirNewOrder() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        let menu = app.buttons["profile.field.0.menu"]
        reveal(menu, in: app)
        menu.tap()
        app.buttons["Move down"].firstMatch.tap()
        XCTAssertEqual(input(app, "profile.field.0.name").value as? String, "About")
        XCTAssertEqual(input(app, "profile.field.1.value").value as? String, rawLink)
        let moved = input(app, "profile.field.1.name")
        moved.tap()
        moved.typeText(" Link")
        attach(app, "profile-fields-reordered")
        save(app)
        openOverview(app)
        reveal(moved, in: app)
        XCTAssertEqual(input(app, "profile.field.0.name").value as? String, "About")
        XCTAssertEqual(moved.value as? String, "Website Link")
        XCTAssertEqual(input(app, "profile.field.1.value").value as? String, rawLink)
    }

    func testDeletingAFieldCanBeDiscarded() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        let menu = app.buttons["profile.field.0.menu"]
        reveal(menu, in: app)
        menu.tap()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertEqual(input(app, "profile.field.0.name").value as? String, "About")
        XCTAssertTrue(app.buttons["profile.edit.save"].isEnabled)
        app.buttons["profile.editor.back"].tap()
        let discard = app.buttons["profile.editor.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        openOverview(app)
        let name = input(app, "profile.field.0.name")
        reveal(name, in: app)
        XCTAssertEqual(name.value as? String, "Website")
        XCTAssertTrue(input(app, "profile.field.2.name").exists)
    }

    func testDeletingAFieldPersistsAndPreservesOtherValues() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        let menu = app.buttons["profile.field.1.menu"]
        reveal(menu, in: app)
        menu.tap()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertEqual(input(app, "profile.field.1.name").value as? String, "Garden")
        XCTAssertFalse(input(app, "profile.field.2.name").exists)
        save(app)
        openOverview(app)
        let name = input(app, "profile.field.1.name")
        reveal(name, in: app)
        XCTAssertEqual(name.value as? String, "Garden")
        XCTAssertEqual(input(app, "profile.field.0.value").value as? String, rawLink)
        XCTAssertFalse(input(app, "profile.field.2.name").exists)
    }

    func testAddingFieldPersistsAndALeftoverBlankRowIsIgnored() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        let add = app.buttons["profile.field.add"]
        reveal(add, in: app)
        add.tap()
        // An empty new row is not a change on its own.
        XCTAssertFalse(app.buttons["profile.edit.save"].isEnabled)
        let name = input(app, "profile.field.3.name")
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Docs")
        let value = input(app, "profile.field.3.value")
        value.tap()
        value.typeText("https://example.com/docs")
        XCTAssertTrue(app.buttons["profile.edit.save"].isEnabled)
        XCTAssertFalse(add.exists, "The fixture server allows four fields")
        // Free a slot and leave the new row blank: saving drops it.
        let menu = app.buttons["profile.field.1.menu"]
        menu.tap()
        app.buttons["Delete"].firstMatch.tap()
        reveal(add, in: app)
        add.tap()
        save(app)
        openOverview(app)
        let last = input(app, "profile.field.2.name")
        reveal(last, in: app)
        XCTAssertEqual(last.value as? String, "Docs")
        XCTAssertEqual(input(app, "profile.field.2.value").value as? String, "https://example.com/docs")
        XCTAssertFalse(input(app, "profile.field.3.name").exists)
        XCTAssertEqual(input(app, "profile.field.0.value").value as? String, rawLink)
    }

    func testHalfFilledFieldBlocksSavingAndSaysWhy() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        let add = app.buttons["profile.field.add"]
        reveal(add, in: app)
        add.tap()
        let name = input(app, "profile.field.3.name")
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Blog")
        app.buttons["profile.edit.save"].tap()
        XCTAssertTrue(app.staticTexts["Complete both fields."].waitForExistence(timeout: 3))
        XCTAssertTrue(name.exists, "The editor stays open so the field can be finished")
        attach(app, "profile-field-incomplete")
    }

    func testDiscardingFieldDraftLeavesStoredValueUnchanged() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        let name = input(app, "profile.field.0.name")
        reveal(name, in: app)
        name.tap()
        name.typeText(" changed")
        app.buttons["profile.editor.back"].tap()
        let discard = app.buttons["profile.editor.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        openOverview(app)
        reveal(name, in: app)
        XCTAssertEqual(name.value as? String, "Website")
        XCTAssertFalse(app.buttons["profile.edit.save"].isEnabled)
    }

    func testBasicNameSavePreservesRawBiography() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        let name = app.textFields["profile.basic.name"]
        let bio = input(app, "profile.basic.bio")
        XCTAssertTrue((bio.value as? String)?.contains(rawLink) == true)
        name.tap()
        name.typeText(" Updated")
        save(app)
        openOverview(app)
        XCTAssertEqual(name.value as? String, "Moro Tester Updated")
        XCTAssertTrue((bio.value as? String)?.contains(rawLink) == true)
    }

    func testImageMenusStageRemovalAndUndo() {
        let app = launch(extra: ["UITEST_PROFILE_MEDIA": "1"])
        defer { app.terminate() }
        openOverview(app)
        let save = app.buttons["profile.edit.save"]
        for (id, remove) in [("avatar", "Remove Avatar"), ("header", "Remove Cover")] {
            let image = app.buttons["profile.edit.\(id)"]
            XCTAssertTrue(image.waitForExistence(timeout: 5))
            image.tap()
            let removeButton = app.buttons[remove].firstMatch
            XCTAssertTrue(removeButton.waitForExistence(timeout: 3))
            attach(app, "profile-\(id)-menu")
            removeButton.tap()
            XCTAssertTrue(save.isEnabled, "Removal is staged until Save")
            image.tap()
            let undo = app.buttons["Undo Change"].firstMatch
            XCTAssertTrue(undo.waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons[remove].exists, "Nothing left to remove once it is staged")
            undo.tap()
            XCTAssertFalse(save.isEnabled)
        }
    }

    func testFeaturedTagSuggestionsAddAndDeletePersist() {
        let app = launch()
        defer { app.terminate() }
        openOverview(app)
        openEditorLink(app, "featuredTags")
        let suggestion = app.buttons["#swift"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
        suggestion.tap()
        let remove = app.buttons["profile.featuredTags.remove.swift"]
        reveal(remove, in: app)
        XCTAssertTrue(remove.exists)
        back(app)
        openEditorLink(app, "featuredTags")
        reveal(remove, in: app)
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        back(app)
        openEditorLink(app, "featuredTags")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
        XCTAssertFalse(remove.exists)
    }

    func testFailedTagDeletionKeepsTheTagVisible() {
        let app = launch(extra: ["UITEST_PROFILE_DELETE_FAILS": "1"])
        defer { app.terminate() }
        openOverview(app)
        openEditorLink(app, "featuredTags")
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
        openEditorLink(app, "localDisplay")
        let local = app.switches["profile.display.featuredTags"]
        XCTAssertTrue(local.waitForExistence(timeout: 8))
        local.tap()
        XCTAssertTrue(["0", "Off"].contains(local.value as? String ?? ""))
        XCTAssertFalse(app.switches["profile.display.media"].exists)
        app.buttons["profile.display.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit.display"].waitForExistence(timeout: 8))
        openEditorLink(app, "display")
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
        openEditorLink(app, "localDisplay")
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
        openEditorLink(app, "display")
        let media = app.switches["profile.display.media"]
        XCTAssertTrue(media.waitForExistence(timeout: 8))
        XCTAssertFalse(media.isEnabled)
        XCTAssertFalse(app.switches["profile.display.featuredTags"].exists)
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
                let window = app.windows.firstMatch.frame
                openOverview(app)
                attach(app, "profile-editor-\(suffix)")
                let name = app.textFields["profile.basic.name"]
                XCTAssertGreaterThanOrEqual(name.frame.minX, 0)
                XCTAssertLessThanOrEqual(name.frame.maxX, window.maxX)
                let value = input(app, "profile.field.0.value")
                reveal(value, in: app)
                XCTAssertGreaterThan(value.frame.width, window.width * 0.6)
                XCTAssertTrue(app.buttons["profile.field.0.menu"].isHittable)
                attach(app, "profile-editor-fields-\(suffix)")
                for destination in ["featuredTags", "display"] {
                    openEditorLink(app, destination)
                    let target = destination == "display"
                        ? app.switches["profile.display.media"] : app.textFields["profile.featuredTags.input"]
                    reveal(target, in: app)
                    XCTAssertTrue(target.exists)
                    XCTAssertGreaterThanOrEqual(target.frame.minX, 0)
                    XCTAssertLessThanOrEqual(target.frame.maxX, window.maxX)
                    attach(app, "profile-\(destination)-\(suffix)")
                    back(app)
                }
                app.terminate()
            }
        }
    }

    private func launch(extra: [String: String] = [:], scheme: String = "light",
        animations: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PROFILE_EXPERIENCE", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_COLOR_SCHEME": scheme]
        if !animations {
            app.launchArguments.append("UITEST_DISABLE_ANIMATIONS")
            app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        }
        app.launchEnvironment.merge(extra) { _, new in new }
        app.launch()
        XCTAssertTrue(app.buttons["profile.moreButton"].waitForExistence(timeout: 10))
        return app
    }

    private func openOverview(_ app: XCUIApplication) {
        let edit = app.buttons["profile.editButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertEqual(edit.label, "Edit Profile")
        edit.tap()
        // The editor is one page; it is ready once the loaded name is editable.
        let name = app.textFields["profile.basic.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: name)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }

    private var limitsExceeded: String { "Some text exceeds this server’s limit. Shorten it before saving." }

    /// Multi-line inputs surface as text views, single-line ones as text fields.
    private func input(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func save(_ app: XCUIApplication) {
        app.buttons["profile.edit.save"].tap()
        XCTAssertTrue(app.buttons["profile.editButton"].waitForExistence(timeout: 8))
    }

    private func openEditorLink(_ app: XCUIApplication, _ destination: String) {
        let link = app.buttons["profile.edit.\(destination)"]
        reveal(link, in: app)
        link.tap()
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
