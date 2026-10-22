import XCTest

/// Opening an image from the feed should show what the feed already loaded right away,
/// instead of a spinner while the full-size file downloads.
@MainActor
final class MediaPreviewReuseUITests: XCTestCase {
    func testViewerShowsTheFeedImageWhileTheFullSizeOneIsStillLoading() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_IMAGE_PREVIEW", "UITEST_DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_IMAGE_PREVIEW_LIST"] = "1"
        // The full-size URL never loads, so anything the viewer shows came from the feed.
        app.launchEnvironment["UITEST_IMAGE_PREVIEW_UNREACHABLE_ORIGINAL"] = "1"
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_COLOR_SCHEME"] = "light"
        app.launch(isolatedFor: self)
        defer { app.terminate() }

        let row = app.otherElements["mediaList.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let feedImage = row.descendants(matching: .image).firstMatch
        XCTAssertTrue(feedImage.waitForExistence(timeout: 10))
        feedImage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.buttons["imagePreview.close"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["imagePreview.image"].firstMatch.waitForExistence(timeout: 2),
            "The viewer should show the image the feed already has")
    }
}
