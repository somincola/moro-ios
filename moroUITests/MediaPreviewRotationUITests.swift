import XCTest

/// The image viewer opened from a post must survive rotation wherever that post sits on screen.
@MainActor
final class MediaPreviewRotationUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testViewerOpenedFromAPostNearTheBottomStaysOpenWhenRotated() {
        assertViewerSurvivesRotation(openingRowAt: 0.85)
    }

    func testViewerOpenedFromAPostNearTheTopStaysOpenWhenRotated() {
        assertViewerSurvivesRotation(openingRowAt: 0.2)
    }

    func testViewerOpenedFromAPostInTheMiddleStaysOpenWhenRotated() {
        assertViewerSurvivesRotation(openingRowAt: 0.5)
    }

    private func assertViewerSurvivesRotation(openingRowAt fraction: CGFloat) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_IMAGE_PREVIEW", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_IMAGE_PREVIEW_LIST"] = "1"
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = "light"
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["mediaList.row.0"].waitForExistence(timeout: 15))

        // Scroll into the feed, then pick the row whose image is nearest the requested height.
        app.swipeUp()
        let window = app.windows.firstMatch.frame
        let targetY = window.minY + window.height * fraction
        let rows = (0..<30).map { app.otherElements["mediaList.row.\($0)"] }.filter { $0.exists }
        let row = try? XCTUnwrap(rows.min { abs($0.frame.midY - targetY) < abs($1.frame.midY - targetY) })
        guard let row else { return XCTFail("No rows on screen") }
        let image = row.descendants(matching: .image).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        // Tap where it is drawn; an element tap would try to scroll the feed first.
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let close = app.buttons["imagePreview.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        // Give the rotation and the feed's relayout time to settle.
        XCTAssertFalse(close.waitForNonExistence(timeout: 3),
            "Rotating must not close the viewer (post at \(Int(fraction * 100))% of the screen)")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertFalse(close.waitForNonExistence(timeout: 3), "Rotating back must not close it either")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }
}
