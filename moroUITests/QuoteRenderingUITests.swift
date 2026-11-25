import XCTest

@MainActor
final class QuoteRenderingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testQuoteRendersAfterMainMediaWithLeftThumbnailAndOpensSwipeableGallery() {
        for scheme in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "UITEST_QUOTE_SHOWCASE",
                "UITEST_DISABLE_ANIMATIONS",
                "-AppleLanguages", "(zh-Hans)",
                "-AppleLocale", "zh_CN",
            ]
            app.launchEnvironment["UITEST_QUOTE_SHOWCASE"] = "1"
            app.launchEnvironment["UITEST_COLOR_SCHEME"] = scheme
            app.launch(isolatedFor: self)
            defer { app.terminate() }

            let quoteMedia = app.buttons["quote.mediaButton"].firstMatch
            XCTAssertTrue(quoteMedia.waitForExistence(timeout: 10))
            let plusBadge = app.staticTexts["+2"].firstMatch
            XCTAssertTrue(plusBadge.waitForExistence(timeout: 5))

            // Main post photo sits ABOVE the quoted post card (and its left media thumbnail).
            let mainPhoto = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Main post banner")).firstMatch
            if mainPhoto.waitForExistence(timeout: 5) {
                XCTAssertLessThan(
                    mainPhoto.frame.maxY,
                    quoteMedia.frame.minY,
                    "Main post media must appear above the quoted post card"
                )
            }

            let cardShot = XCTAttachment(screenshot: app.screenshot())
            cardShot.name = "quote-card-showcase-\(scheme)"
            cardShot.lifetime = .keepAlways
            add(cardShot)

            if scheme == "light" {
                // Tapping the left media thumbnail opens the fullscreen swipeable gallery.
                quoteMedia.tap()
                let closeButton = app.buttons.matching(
                    NSPredicate(format: "identifier == 'imagePreview.close' OR label == '关闭' OR label == 'Close'")
                ).firstMatch
                let pagerExists = app.staticTexts["1 / 3"].waitForExistence(timeout: 5)
                    || closeButton.waitForExistence(timeout: 5)
                XCTAssertTrue(pagerExists, "Tapping quoted media thumbnail should open the media viewer")

                let galleryShot = XCTAttachment(screenshot: app.screenshot())
                galleryShot.name = "quote-media-viewer-open"
                galleryShot.lifetime = .keepAlways
                add(galleryShot)

                // Swipe to second quoted photo in the gallery.
                app.windows.firstMatch.swipeLeft()
                if closeButton.exists {
                    closeButton.tap()
                } else {
                    app.windows.firstMatch.swipeDown()
                }
                XCTAssertTrue(quoteMedia.waitForExistence(timeout: 5))

                // Tapping non-media region of the quote card opens the quoted status.
                let quoteCardAuthor = app.descendants(matching: .any).matching(
                    NSPredicate(format: "label CONTAINS %@", "鱼哥")
                ).firstMatch
                XCTAssertTrue(quoteCardAuthor.waitForExistence(timeout: 5))
                quoteCardAuthor.tap()
                let tapResult = app.staticTexts["quoteShowcase.tapResult"]
                XCTAssertTrue(tapResult.wait(for: \.label, toEqual: "quoteTap:quoted-multi-media", timeout: 5))
            }
        }
    }
}
