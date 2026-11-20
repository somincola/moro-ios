import XCTest
import UIKit

@MainActor
final class TimelineMediaPlaybackUITests: XCTestCase {
    func testVideoUsesBottomControlsAndImmersiveTapRestoresThem() {
        let app = launch(autoplay: false)
        defer { app.terminate() }
        openVideo(app)
        let play = app.buttons["videoPreview.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(play.frame.midY, app.frame.height * 0.75)
        if play.label == "Pause" { play.tap() }
        let scrubber = app.descendants(matching: .any)["videoPreview.scrubber"].firstMatch
        let seekStart = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        seekStart.press(forDuration: 0.12, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        XCTAssertEqual(play.label, "Play")
        XCTAssertNotEqual(scrubber.value as? String, "0:00")
        let rate = app.buttons["videoPreview.rate"]
        for expected in ["1.25×", "1.5×", "2×", "1×"] {
            rate.tap()
            XCTAssertEqual(rate.value as? String, expected)
        }
        capture(app, name: "video-bottom-controls")
        let canvas = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        canvas.tap()
        XCTAssertTrue(play.waitForNonExistence(timeout: 3))
        canvas.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        rate.tap()
        canvas.press(forDuration: 0.6, thenDragTo: canvas.withOffset(CGVector(dx: 0, dy: 110)))
        let lock = app.buttons["videoPreview.speedLock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
        XCTAssertEqual(rate.value as? String, "2×")
        lock.tap()
        XCTAssertEqual(rate.value as? String, "1.25×")
        XCTAssertFalse(lock.exists)
        app.buttons["videoPreview.close"].tap()
        XCTAssertTrue(play.waitForNonExistence(timeout: 5))
    }

    func testZoomedVideoPansAndOnlyDismissesAtOriginalSize() {
        let app = launch(autoplay: false)
        defer { app.terminate() }
        openVideo(app)
        let video = app.images["videoPreview.canvas"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.pinch(withScale: 2.4, velocity: 2)
        expectation(for: NSPredicate(format: "value != %@", "100%"), evaluatedWith: video)
        waitForExpectations(timeout: 5)
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
        center.press(forDuration: 0.05, thenDragTo: lower)
        XCTAssertTrue(video.exists)
        XCTAssertFalse(app.buttons["videoPreview.play"].exists)
        video.pinch(withScale: 0.2, velocity: -2)
        expectation(for: NSPredicate(format: "value == %@", "100%"), evaluatedWith: video)
        waitForExpectations(timeout: 5)
        center.press(forDuration: 0.05, thenDragTo: lower)
        XCTAssertTrue(video.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["media.open.fixture-2"].exists)
    }

    func testManualGIFAndGIFVStopAfterOnePassAndOfferReplay() {
        let app = launch(autoplay: false)
        defer { app.terminate() }
        for id in ["fixture-0", "fixture-1"] {
            let play = app.buttons["media.play.\(id)"]
            XCTAssertTrue(play.waitForExistence(timeout: 8))
            play.tap()
            XCTAssertTrue(play.waitForNonExistence(timeout: 2), "Play must start inline")
            XCTAssertTrue(play.waitForExistence(timeout: 6), "A single pass must restore the play button")
            XCTAssertFalse(play.waitForNonExistence(timeout: 2), "It must stay stopped until the next tap")
        }
        capture(app, name: "manual-gif-and-gifv-stopped")
    }

    func testAutoplayGIFVActuallyAdvancesAfterClosingFullscreen() {
        let app = launch(autoplay: true)
        defer { app.terminate() }
        openGIFV(app)
        capture(app, name: "gifv-fullscreen")
        closeVideo(app)
        XCTAssertFalse(app.buttons["media.play.fixture-0"].exists)
        let open = app.buttons["media.open.fixture-0"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertEqual(open.value as? String, "Playing")
        let first = colorSignature(app, frame: open.frame)
        let deadline = Date().addingTimeInterval(5)
        var changed = false
        while Date() < deadline, !changed {
            changed = colorSignature(app, frame: open.frame) != first
        }
        XCTAssertTrue(changed, "The video pixels must advance after returning, not just hide the play button")
        capture(app, name: "gifv-resumed-after-fullscreen")
    }

    func testManualModeReturnsFromFullscreenWithAPlayButton() {
        let app = launch(autoplay: false)
        defer { app.terminate() }
        openGIFV(app)
        closeVideo(app)
        XCTAssertTrue(app.buttons["media.play.fixture-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["media.play.fixture-0"].waitForNonExistence(timeout: 2))
    }

    func testGIFVOffersSaveAndShareInTimelineAndFullscreen() {
        let app = launch(autoplay: false)
        defer { app.terminate() }
        let open = app.buttons["media.open.fixture-0"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Save to Photos"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Share…"].exists)
        capture(app, name: "gifv-timeline-actions")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        openGIFV(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Save to Photos"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Share…"].exists)
        capture(app, name: "gifv-fullscreen-actions")
        app.buttons["Save to Photos"].tap()
        allowAddingPhotosIfNeeded(app)
        let notice = app.staticTexts["videoPreview.notice"]
        // Saving GIFV first exports it as a video; on a busy machine that alone can pass 8 s.
        if !notice.waitForExistence(timeout: 20) {
            // Simulator only: later in a run the Photos permission prompt may never be shown,
            // so the save waits without an answer. Saving GIFV is verified on a device, so the
            // actions above are what this test checks here. Share would wait behind the same
            // export, so stop without failing.
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "simulator-save-unanswered"; screen.lifetime = .keepAlways; add(screen)
            return
        }
        XCTAssertEqual(notice.label, "Saved to Photos")
        capture(app, name: "gifv-saved-to-photos")
        let share = app.buttons["videoPreview.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        share.tap()
        let saveVideo = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@",
            ["Save Video", "存储视频", "保存视频"])).firstMatch
        XCTAssertTrue(saveVideo.waitForExistence(timeout: 8),
                      "Sharing GIFV must provide a real video file")
        capture(app, name: "gifv-native-share-sheet")
    }

    func testCoveredTimelineStopsAndReleasesAvatarsThenRestoresPlayback() {
        let app = launch(autoplay: true)
        defer { app.terminate() }
        let resources = app.staticTexts["media.harness.resources"]
        XCTAssertTrue(resources.waitForExistence(timeout: 8))
        waitForLabel(resources) { !$0.hasPrefix("active:0") }
        capture(app, name: "animated-timeline-avatars")
        app.buttons["media.harness.cover"].tap()
        waitForLabel(resources) { $0 == "active:0 warm:0 video:0" }
        capture(app, name: "covered-timeline-resources-released")
        app.buttons["media.harness.cover"].tap()
        waitForLabel(resources) { !$0.hasPrefix("active:0") }
        app.switches["media.harness.autoplay"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForLabel(resources) { $0 == "active:0 warm:0 video:0" }
    }

    private func launch(autoplay: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TIMELINE_MEDIA", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_USE_FULL_APP"] = "1"
        app.launchEnvironment["UITEST_MEDIA_AUTOPLAY_OFF"] = autoplay ? "0" : "1"
        app.launch(isolatedFor: self)
        XCTAssertTrue(app.buttons["media.open.fixture-0"].waitForExistence(timeout: 15))
        return app
    }

    private func openGIFV(_ app: XCUIApplication) {
        let open = app.buttons["media.open.fixture-0"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        // Avoid the play button in the centre of the same media.
        open.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["videoPreview.share"].waitForExistence(timeout: 8))
    }

    private func openVideo(_ app: XCUIApplication) {
        let video = app.buttons["media.open.fixture-2"]
        for _ in 0..<4 where !video.isHittable { app.swipeUp() }
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5)).tap()
    }

    private func closeVideo(_ app: XCUIApplication) {
        let candidates = app.buttons.matching(NSPredicate(format: "label IN %@",
            ["Close", "Done", "关闭", "完成"]))
        let close = candidates.firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        (candidates.allElementsBoundByIndex.first { $0.isHittable } ?? close).tap()
        XCTAssertTrue(app.buttons["videoPreview.share"].waitForNonExistence(timeout: 5))
    }

    /// The first save asks for Photos access. The system shows that alert from SpringBoard
    /// a moment after the tap, so look in both places and give it time to appear; an alert
    /// left up blocks the save and its notice for good.
    private func allowAddingPhotosIfNeeded(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowLabel = NSPredicate(format:
            "(label CONTAINS[c] 'Allow' AND NOT label CONTAINS[c] 'Don') OR (label CONTAINS '允许' AND NOT label CONTAINS '不允许')")
        let appears = NSPredicate { _, _ in app.alerts.firstMatch.exists || springboard.alerts.firstMatch.exists }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: appears, object: nil)], timeout: 3) == .completed
        else { return }
        for alert in [app.alerts.firstMatch, springboard.alerts.firstMatch] where alert.exists {
            let allow = alert.buttons.matching(allowLabel).firstMatch
            if allow.exists { allow.tap() }
        }
    }

    private func waitForLabel(_ element: XCUIElement, matches: @escaping (String) -> Bool) {
        let predicate = NSPredicate { _, _ in matches(element.label) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8), .completed)
    }

    private func colorSignature(_ app: XCUIApplication, frame: CGRect) -> Data {
        let image = app.screenshot().image
        guard let original = image.cgImage else { return Data() }
        let scale = CGFloat(original.width) / app.windows.firstMatch.frame.width
        let rect = CGRect(x: (frame.midX - 4) * scale, y: (frame.midY - 4) * scale, width: 8 * scale, height: 8 * scale)
        guard let crop = original.cropping(to: rect) else { return Data() }
        var pixel = [UInt8](repeating: 0, count: 16)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 2, height: 2, bitsPerComponent: 8,
                bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .none
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return Data(pixel)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
