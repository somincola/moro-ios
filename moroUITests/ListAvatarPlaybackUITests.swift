import XCTest
import UIKit

@MainActor
final class ListAvatarPlaybackUITests: XCTestCase {
    func testSearchAccountsAndPostsStopInHiddenPagesAndFollowTheGIFSetting() {
        let app = launch()
        defer { app.terminate() }
        let table = app.tables["search.results"]
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 12))
        waitForActiveAvatars(app)
        let account = table.cells.firstMatch
        assertAvatarPixelsAdvance(app, point: CGPoint(x: account.frame.minX + 32, y: account.frame.minY + 22))
        capture(app, name: "search-animated-account")
        app.buttons["mainTab.explore"].tap()
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 5))
        waitForActiveAvatars(app)
        assertAvatarPixelsAdvance(app, point: CGPoint(x: table.cells.firstMatch.frame.minX + 32,
            y: table.cells.firstMatch.frame.minY + 22))

        toggleAutoplay(app)
        waitForReleasedAvatars(app)
        toggleAutoplay(app)
        waitForActiveAvatars(app)
        app.searchFields["search.input"].tap()
        XCTAssertTrue(app.buttons["search.cancel"].waitForExistence(timeout: 3))
        waitForReleasedAvatars(app)
        app.buttons["search.cancel"].tap()
        waitForActiveAvatars(app)

        table.cells.firstMatch.tap()
        waitForReleasedAvatars(app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 5))
        waitForActiveAvatars(app)

        app.segmentedControls["search.scope"].buttons.element(boundBy: 1).tap()
        waitForActiveAvatars(app)
        capture(app, name: "search-animated-post-author")
        app.buttons["mainTab.home"].tap()
        waitForReleasedAvatars(app)
        app.buttons["mainTab.explore"].tap()
        waitForActiveAvatars(app)

        app.segmentedControls["search.scope"].buttons.element(boundBy: 0).tap()
        let input = app.searchFields["search.input"]
        input.tap()
        input.typeText("long\n")
        XCTAssertTrue(table.cells.matching(NSPredicate(format: "label CONTAINS %@", "Result long 0")).firstMatch.waitForExistence(timeout: 5))
        table.swipeUp()
        table.swipeUp()
        waitForActiveAvatars(app)
        assertBoundedResources(app)
        capture(app, name: "search-reused-avatar-cells")
    }

    func testNotificationsAnimateSingleAndGroupedAvatarsAndReleaseBehindRoutes() {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tables["search.results"].cells.firstMatch.waitForExistence(timeout: 12))
        app.buttons["mainTab.inbox"].tap()
        let actors = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notifications.actors.")).firstMatch
        XCTAssertTrue(actors.waitForExistence(timeout: 8))
        waitForActiveAvatars(app)
        assertBoundedResources(app)
        capture(app, name: "notifications-animated-single-and-grouped-avatars")
        actors.tap()
        let actor = app.buttons["notifications.actor.notification-actor-0"]
        XCTAssertTrue(actor.waitForExistence(timeout: 5))
        waitForResources(app) { $0.hasPrefix("active:3 ") }
        capture(app, name: "notifications-animated-actors-sheet")
        actor.tap()
        waitForReleasedAvatars(app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(actors.waitForExistence(timeout: 5))
        waitForActiveAvatars(app)

        toggleAutoplay(app)
        waitForReleasedAvatars(app)
        toggleAutoplay(app)
        waitForActiveAvatars(app)
        let list = app.scrollViews["notifications.list"]
        XCTAssertTrue(list.exists)
        list.swipeUp()
        list.swipeUp()
        waitForActiveAvatars(app)
        assertBoundedResources(app)
        app.buttons["mainTab.home"].tap()
        waitForReleasedAvatars(app)
        capture(app, name: "notification-hidden-page-resources-released")
        app.buttons["mainTab.inbox"].tap()
        waitForActiveAvatars(app)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SEARCH_FLOW", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_SEARCH_NATIVE_SHELL"] = "1"
        app.launchEnvironment["UITEST_ANIMATED_LIST_AVATARS"] = "1"
        app.launch(isolatedFor: self)
        return app
    }

    private func toggleAutoplay(_ app: XCUIApplication) {
        app.switches["listAvatars.autoplay"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func waitForActiveAvatars(_ app: XCUIApplication) {
        waitForResources(app) { $0.hasPrefix("active:") && !$0.hasPrefix("active:0 ") }
    }

    private func waitForReleasedAvatars(_ app: XCUIApplication) {
        waitForResources(app) { $0 == "active:0 warm:0" }
    }

    private func waitForResources(_ app: XCUIApplication, matches: @escaping (String) -> Bool) {
        let resources = app.staticTexts["listAvatars.resources"]
        XCTAssertTrue(resources.waitForExistence(timeout: 5))
        let predicate = NSPredicate { _, _ in matches(resources.label) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8), .completed,
            resources.label)
    }

    private func assertBoundedResources(_ app: XCUIApplication) {
        let label = app.staticTexts["listAvatars.resources"].label
        let counts = label.split(separator: " ").compactMap { Int($0.split(separator: ":").last ?? "") }
        XCTAssertEqual(counts.count, 2)
        if counts.count == 2 {
            XCTAssertLessThanOrEqual(counts[0] + counts[1], 8)
            XCTAssertLessThanOrEqual(counts[1], 2)
        }
    }

    private func assertAvatarPixelsAdvance(_ app: XCUIApplication, point: CGPoint) {
        let first = signature(app, point: point)
        let deadline = Date().addingTimeInterval(5)
        var changed = false
        while Date() < deadline, !changed { changed = signature(app, point: point) != first }
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(changed, "The search avatar must advance real GIF frames")
    }

    private func signature(_ app: XCUIApplication, point: CGPoint) -> Data {
        guard let image = app.screenshot().image.cgImage else { return Data() }
        let scale = CGFloat(image.width) / app.windows.firstMatch.frame.width
        guard let cropped = image.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 2 * scale, height: 2 * scale)) else { return Data() }
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cropped, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return Data(bytes)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
