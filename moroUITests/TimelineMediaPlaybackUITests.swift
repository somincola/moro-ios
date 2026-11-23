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
        // The 160×96 fixture is a solid color. Check both edges of the elevated video
        // against its center in one decoded frame, independently of which frame is paused.
        let frame = app.frame
        let screenshot = app.screenshot().image
        func sample(at y: CGFloat) -> Data {
            let point = CGRect(origin: CGPoint(x: frame.midX, y: y), size: .zero)
            return colorSignature(app, frame: point, image: screenshot)
        }
        let halfVideoHeight = frame.width * 0.3
        let centerColor = sample(at: frame.midY)
        XCTAssertFalse(centerColor.isEmpty)
        XCTAssertEqual(sample(at: frame.midY - halfVideoHeight - 20), centerColor)
        XCTAssertNotEqual(sample(at: frame.midY + halfVideoHeight - 20), centerColor)
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
        XCTAssertEqual(lock.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(lock.frame.width, lock.frame.height)
        capture(app, name: "centered-speed-lock")
        XCTAssertTrue(lock.waitForNonExistence(timeout: 6))
        XCTAssertEqual(rate.value as? String, "2×")
        canvas.press(forDuration: 0.6, thenDragTo: canvas.withOffset(CGVector(dx: 0, dy: 110)))
        XCTAssertEqual(rate.value as? String, "1.25×")
        XCTAssertFalse(lock.exists)
        app.buttons["videoPreview.close"].tap()
        XCTAssertTrue(play.waitForNonExistence(timeout: 5))
    }

    func testDraggingNearTheDockTargetKeepsTheVideoSessionAcrossHome() throws {
        let app = launch(autoplay: false)
        defer { app.terminate() }
        openVideo(app)
        let rate = app.buttons["videoPreview.rate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 6))
        let pip = app.buttons["videoPreview.pip"]
        try XCTSkipUnless(pip.exists, "AVKit does not offer system Picture in Picture on this device.")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: pip)
        waitForExpectations(timeout: 8)
        rate.tap()
        XCTAssertEqual(rate.value as? String, "1.25×")

        // Release above the button itself, inside the capture radius.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.06,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.87)),
            withVelocity: XCUIGestureVelocity(rawValue: 450), thenHoldForDuration: 0.22)
        XCTAssertTrue(rate.waitForNonExistence(timeout: 6))
        XCTAssertTrue(app.buttons["media.open.fixture-2"].waitForExistence(timeout: 4))
        XCUIDevice.shared.press(.home)
        app.activate()
        openVideo(app)
        XCTAssertTrue(rate.waitForExistence(timeout: 6))
        XCTAssertEqual(rate.value as? String, "1.25×", "Opening the docked post should restore the original session.")
    }

    func testFullscreenVideoLoopsFromTheEndAtTheSelectedRate() {
        let app = launch(autoplay: false)
        defer { app.terminate() }
        openVideo(app)
        let play = app.buttons["videoPreview.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        if play.label == "Pause" { play.tap() }
        let rate = app.buttons["videoPreview.rate"]
        rate.tap()
        let scrubber = app.descendants(matching: .any)["videoPreview.scrubber"].firstMatch
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let nearEnd = NSPredicate { _, _ in
            guard let value = scrubber.value as? String else { return false }
            return (Int(value.split(separator: ":").last ?? "") ?? 0) > 20
        }
        expectation(for: nearEnd, evaluatedWith: scrubber)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(play.label, "Play")
        play.tap()
        let advancedAgain = NSPredicate { _, _ in
            guard let time = scrubber.value as? String, let seconds = Int(time.split(separator: ":").last ?? "") else { return false }
            return (1...9).contains(seconds) && play.label == "Pause"
        }
        expectation(for: advancedAgain, evaluatedWith: scrubber)
        waitForExpectations(timeout: 12)
        XCTAssertEqual(rate.value as? String, "1.25×")
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
        XCTAssertFalse(app.buttons["Save to Photos"].exists)
        let menu = app.buttons["mediaPreview.more"]
        menu.tap()
        XCTAssertTrue(app.buttons["Save to Photos"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Share…"].exists)
        capture(app, name: "gifv-fullscreen-actions")
        app.buttons["Save to Photos"].tap()
        XCTAssertEqual(photoSaveResult(in: app), "Saved to Photos")
        capture(app, name: "gifv-saved-to-photos")
        menu.tap()
        let share = app.buttons["Share…"]
        // The system menu is presented again after Photos finishes. Its actions can be
        // in the accessibility hierarchy before the opening transition accepts a tap.
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.wait(for: \.isHittable, toEqual: true, timeout: 5))
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
        XCTAssertTrue(app.buttons["mediaPreview.more"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.buttons["mediaPreview.more"].waitForNonExistence(timeout: 5))
    }

    /// An already-authorized save can finish and dismiss its toast while waiting for a permission alert.
    private func photoSaveResult(in app: XCUIApplication) -> String? {
        let notice = app.staticTexts["videoPreview.notice"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alerts = [app.alerts.firstMatch, springboard.alerts.firstMatch]
        let permissionOrResult = NSPredicate { _, _ in notice.exists || alerts.contains { $0.exists } }
        if !notice.exists {
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: permissionOrResult, object: nil)], timeout: 15)
        }
        if notice.exists { return notice.label }
        let allowLabel = NSPredicate(format:
            "(label CONTAINS[c] 'Allow' AND NOT label CONTAINS[c] 'Don') OR (label CONTAINS '允许' AND NOT label CONTAINS '不允许')")
        for alert in alerts where alert.exists {
            let allow = alert.buttons.matching(allowLabel).firstMatch
            if allow.exists {
                allow.tap()
                break
            }
        }
        return notice.waitForExistence(timeout: 15) ? notice.label : nil
    }

    private func waitForLabel(_ element: XCUIElement, matches: @escaping (String) -> Bool) {
        let predicate = NSPredicate { _, _ in matches(element.label) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8), .completed)
    }

    private func colorSignature(_ app: XCUIApplication, frame: CGRect, image: UIImage? = nil) -> Data {
        let image = image ?? app.screenshot().image
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
