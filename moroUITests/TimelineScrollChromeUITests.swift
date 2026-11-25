//
//  TimelineScrollChromeUITests.swift
//  moroUITests
//
//  Verifies the Liquid Glass home compose button layout and scroll-driven header
//  collapse + compose button hide/reveal behavior.
//

import XCTest

@MainActor
final class TimelineScrollChromeUITests: XCTestCase {
    func testHomeHeaderCollapsesOnScrollDownAndRestoresOnScrollUpWithGlassComposeButton() {
        continueAfterFailure = false

        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["APP_STORE_SCREENSHOTS", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment = [
            "UITEST_USE_FULL_APP": "1",
            "UITEST_COLOR_SCHEME": "light",
        ]
        app.launch(isolatedFor: self)

        let composeButton = app.buttons["home.composeButton"]
        let drawerButton = app.buttons["home.drawerButton"]
        let tabBar = app.tabBars.firstMatch

        XCTAssertTrue(composeButton.waitForExistence(timeout: 20))
        XCTAssertTrue(drawerButton.waitForExistence(timeout: 10))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        // Verify Liquid Glass compose button geometry matches production layout contract
        // and aligns flush with the floating tab bar capsule's trailing margin (~21pt).
        let window = app.windows.firstMatch
        XCTAssertLessThanOrEqual(composeButton.frame.width, 64)
        XCTAssertLessThanOrEqual(composeButton.frame.height, 64)
        XCTAssertLessThan(abs(composeButton.frame.width - composeButton.frame.height), 2)
        XCTAssertLessThanOrEqual(composeButton.frame.maxY, tabBar.frame.minY - 4)
        XCTAssertGreaterThanOrEqual(window.frame.maxX - composeButton.frame.maxX, 20)
        XCTAssertTrue(drawerButton.isHittable)
        let expandedDrawerMinY = drawerButton.frame.minY
        attach(app, named: "home-glass-top-light")

        // Scroll down past the top (twice to also exercise bottom rubber-band bounce).
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10))
        scrollView.swipeUp(velocity: .default)
        scrollView.swipeUp(velocity: .default)

        // Header should stay collapsed above the viewport even after bottom bounce.
        let collapsedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !drawerButton.exists || (!drawerButton.isHittable && drawerButton.frame.minY < expandedDrawerMinY - 36)
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [collapsedExpectation], timeout: 5),
            .completed,
            "Expected floating home header to stay collapsed after scrolling down (minY=\(drawerButton.frame.minY), hittable=\(drawerButton.isHittable))"
        )

        // Once scrolling settles, the compose button should gracefully reveal again.
        let composeRevealedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in composeButton.exists && composeButton.isHittable },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [composeRevealedExpectation], timeout: 5),
            .completed,
            "Expected compose button to reappear after scrolling settles"
        )
        attach(app, named: "home-scrolled-collapsed-header-light")

        // Scrolling back up brings the floating header right back.
        scrollView.swipeDown(velocity: .default)
        let restoredExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                drawerButton.exists && drawerButton.isHittable && drawerButton.frame.minY >= expandedDrawerMinY - 4
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [restoredExpectation], timeout: 5),
            .completed,
            "Expected floating home header to reappear when scrolling back up (minY=\(drawerButton.frame.minY), hittable=\(drawerButton.isHittable))"
        )
        XCTAssertTrue(composeButton.isHittable)
        attach(app, named: "home-scrolled-restored-header-light")
    }

    func testHomeGlassComposeButtonInDarkMode() {
        continueAfterFailure = false

        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["APP_STORE_SCREENSHOTS", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment = [
            "UITEST_USE_FULL_APP": "1",
            "UITEST_COLOR_SCHEME": "dark",
        ]
        app.launch(isolatedFor: self)

        let composeButton = app.buttons["home.composeButton"]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 20))
        XCTAssertTrue(composeButton.isHittable)
        attach(app, named: "home-glass-top-dark")
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
