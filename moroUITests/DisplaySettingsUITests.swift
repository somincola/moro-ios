import XCTest

@MainActor
final class DisplaySettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLinkColorPersistsAfterRelaunch() {
        let app = makeApp()
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        openDisplay(app)
        XCTAssertEqual(app.buttons["display.appearance.0"].label, "System")
        XCTAssertEqual(
            app.staticTexts["display.section.appearance"].frame.height,
            app.staticTexts["display.section.theme-color"].frame.height,
            accuracy: 1
        )
        for title in ["Blue", "Yellow", "Pink", "Purple", "Orange", "Green"] {
            XCTAssertFalse(app.staticTexts[title].exists)
        }
        XCTAssertFalse(app.staticTexts["Preview"].exists)
        XCTAssertTrue(app.staticTexts["Theme"].exists)
        tap("display.color.blue", in: app)
        tap("display.color.purple", in: app)
        XCTAssertTrue(app.buttons["display.color.purple"].isSelected)
        XCTAssertFalse(app.buttons["display.color.blue"].isSelected)
        attach(app, name: "display-purple-light")

        app.terminate()
        app.launch(isolatedFor: self)
        openDisplay(app)
        let purple = app.buttons["display.color.purple"]
        XCTAssertTrue(purple.isSelected)
        tap("display.color.blue", in: app)
    }

    func testDisplaySupportsChineseDarkModeAndLargestText() {
        let app = makeApp()
        app.launchArguments = [
            "UITEST_SETTINGS_SHEET", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
        ]
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = "dark"
        app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = "accessibilityXXXL"
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        openDisplay(app)
        XCTAssertTrue(app.navigationBars["外观"].exists)
        XCTAssertEqual(app.buttons["display.appearance.0"].label, "系统")
        XCTAssertGreaterThan(
            app.staticTexts["display.section.appearance"].frame.height, 40,
            "Largest Dynamic Type must actually be applied"
        )
        attach(app, name: "display-chinese-dark-largest-text-heading")
        for name in ["blue", "yellow", "pink", "purple", "orange", "green"] {
            tap("display.color.\(name)", in: app)
            let button = app.buttons["display.color.\(name)"]
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isSelected)
            // Layout rounding reports 44 pt as 43.99999999999997.
            XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.01)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.01)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.windows.firstMatch.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.windows.firstMatch.frame.maxX)
        }
        attach(app, name: "display-chinese-dark-largest-text")
        tap("display.color.blue", in: app)
    }

    func testAppearanceCardsSelectWhenTappedAwayFromLabel() {
        let app = makeApp()
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        openDisplay(app)
        XCTAssertEqual(app.buttons["display.appearance.0"].label, "System")
        for rawValue in [1, 2, 0] {
            let card = app.buttons["display.appearance.\(rawValue)"]
            XCTAssertTrue(card.isHittable)
            XCTAssertGreaterThanOrEqual(card.frame.width, 80)
            XCTAssertGreaterThanOrEqual(card.frame.height, 100)
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
            XCTAssertTrue(card.isSelected)
            for other in [0, 1, 2] where other != rawValue {
                XCTAssertFalse(app.buttons["display.appearance.\(other)"].isSelected)
            }
        }
        attach(app, name: "display-appearance-cards")
    }

    func testCustomColorPickerOpensAndSelectionPersists() {
        let app = makeApp()
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        openDisplay(app)
        tap("display.color.blue", in: app)
        tap("display.color.custom", in: app)
        // Pick a swatch in the native grid. The picker's sliders are not exposed as
        // XCUI sliders, so adjusting "the first slider" never changed the color.
        let grid = app.buttons["Grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.tap()
        let swatch = app.otherElements
            .matching(NSPredicate(format: "label BEGINSWITH %@", "dark purple")).firstMatch
        XCTAssertTrue(swatch.waitForExistence(timeout: 5))
        swatch.tap()
        attach(app, name: "display-native-custom-color-picker")
        let close = app.buttons["close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let custom = app.descendants(matching: .any)["display.color.custom"]
        XCTAssertGreaterThanOrEqual(custom.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(custom.frame.height, 44 - 0.01)
        XCTAssertTrue(custom.isSelected)
        let selectedColorDescription = custom.value as? String
        attach(app, name: "display-custom-color")
        app.terminate()
        app.launch(isolatedFor: self)
        openDisplay(app)
        XCTAssertTrue(app.descendants(matching: .any)["display.color.custom"].isSelected)
        XCTAssertEqual(app.descendants(matching: .any)["display.color.custom"].value as? String, selectedColorDescription)
        tap("display.color.blue", in: app)
    }

    func testUnknownPreferenceFallsBackToBlue() {
        let app = makeApp()
        app.launchArguments += ["-contentLinkColor", "unknown-color"]
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        openDisplay(app)
        let blue = app.buttons["display.color.blue"]
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        XCTAssertTrue(blue.isSelected)
    }

    func testFourPostTextSizesUpdatePreviewAndPersist() {
        let app = makeApp()
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        openDisplay(app)
        tap("display.font-size", in: app)
        let slider = app.sliders["display.font-size"]
        let preview = app.descendants(matching: .any)["display.preview"]
        let trackY = slider.frame.midY
        let previewHeight = preview.frame.height
        for (index, title) in ["Small", "Standard", "Large", "Extra large"].enumerated() {
            slider.adjust(toNormalizedSliderPosition: CGFloat(index) / 3)
            XCTAssertEqual(slider.value as? String, title)
            XCTAssertEqual(slider.normalizedSliderPosition, CGFloat(index) / 3, accuracy: 0.02)
            XCTAssertEqual(slider.frame.midY, trackY, accuracy: 1, "Preview wrapping must not move the thumb while dragging")
            XCTAssertEqual(preview.frame.height, previewHeight, accuracy: 1)
        }
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        XCTAssertEqual(slider.value as? String, "Small")
        XCTAssertEqual(slider.frame.midY, trackY, accuracy: 1)
        // The thumb is held on a detent between steps; a slow drag must still walk all of them.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)),
            withVelocity: XCUIGestureVelocity(80),
            thenHoldForDuration: 0.1
        )
        XCTAssertEqual(slider.value as? String, "Extra large")
        XCTAssertEqual(slider.normalizedSliderPosition, 1, accuracy: 0.02)
        slider.adjust(toNormalizedSliderPosition: 0.43)
        XCTAssertEqual(slider.value as? String, "Standard", "Release between detents must select the nearest size")
        XCTAssertEqual(slider.normalizedSliderPosition, 1.0 / 3, accuracy: 0.02)
        slider.adjust(toNormalizedSliderPosition: 1)
        attach(app, name: "display-extra-large-post-text")
        app.terminate()
        app.launch(isolatedFor: self)
        openDisplay(app)
        XCTAssertEqual(app.sliders["display.font-size"].value as? String, "Extra large")
        tap("display.font-size", in: app)
        app.sliders["display.font-size"].adjust(toNormalizedSliderPosition: 1.0 / 3)
        XCTAssertEqual(app.sliders["display.font-size"].value as? String, "Standard")
        app.navigationBars.buttons.firstMatch.tap()
        tap("settings.display", in: app)
        XCTAssertEqual(app.sliders["display.font-size"].value as? String, "Standard")
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SETTINGS_SHEET", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launchEnvironment["UITEST_SETTINGS_SHEET"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = "light"
        return app
    }

    private func openDisplay(_ app: XCUIApplication) {
        tap("settings.display", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["display.preview"].waitForExistence(timeout: 5))
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = settingsElement(identifier, in: app)
        // A control whose center sits in the home-indicator strip reports hittable,
        // but the system gesture area swallows the tap; scroll it fully into view.
        let visibleMaxY = app.windows.firstMatch.frame.maxY - 60
        for _ in 0..<8 where !element.exists || !element.isHittable || element.frame.maxY > visibleMaxY {
            let scrollView = scrollContainer(app)
            if element.exists && element.frame.width > 0 && element.frame.maxY < scrollView.frame.minY {
                scrollView.swipeDown()
            } else {
                scrollView.swipeUp()
            }
        }
        for _ in 0..<8 where !element.exists || !element.isHittable {
            scrollContainer(app).swipeDown()
        }
        if !element.exists || !element.isHittable { attach(app, name: "display-unreachable-\(identifier)") }
        XCTAssertTrue(element.exists, identifier)
        XCTAssertTrue(element.isHittable, identifier)
        element.tap()
    }

    /// Settings pages are grouped Lists (collection views); the home sheet may still be a scroll view.
    private func scrollContainer(_ app: XCUIApplication) -> XCUIElement {
        let list = app.collectionViews.firstMatch
        return list.exists ? list : app.scrollViews.firstMatch
    }

    /// Typed queries first: an `.any` query fetches attributes for every element,
    /// and that logging volume can get the app's log client quarantined.
    private func settingsElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 3) { return button }
        let slider = app.sliders[identifier]
        if slider.exists { return slider }
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        _ = element.waitForExistence(timeout: 1)
        return element
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
