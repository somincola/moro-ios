import XCTest
import UIKit

@MainActor
final class PostEmojiPlaybackUITests: XCTestCase {
    func testComposerPlaysTheInsertedGlyphWithEitherKeyboardAndKeepsTheShortcode() throws {
        for mode in ["new", "mentions"] {
            let app = openComposer(mode: mode, playback: true)
            defer { app.terminate() }
            let editor = app.textViews["compose.textInput"]
            if mode == "new" {
                editor.typeText(":ani")
                let suggestion = app.buttons["compose.suggestion.emoji.animated"]
                XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
                suggestion.tap()
            } else {
                app.buttons["compose.emojiToggle"].tap()
                let gif = app.buttons[":gif:"]
                XCTAssertTrue(gif.waitForExistence(timeout: 5))
                gif.tap()
            }
            try verifyAnimation(in: editor, app: app)
            if mode == "mentions" {
                app.buttons["compose.emojiToggle"].tap()
                try verifyAnimation(in: editor, app: app)
            }
            let before = try XCTUnwrap(editor.value as? String)
            XCTAssertTrue(before.contains(mode == "new" ? ":animated:" : ":gif:"))
            editor.typeText("a")
            XCTAssertEqual(editor.value as? String, before + "a")
            editor.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(editor.value as? String, before)
            editor.typeText("\n:webp:")
            try verifyAnimation(in: editor, app: app, count: 2)
            editor.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(editor.value as? String, before + "\n")
        }
    }

    func testComposerKeepsThePosterWhenEmojiPlaybackIsOff() throws {
        let app = openComposer(mode: "new", playback: false)
        defer { app.terminate() }
        let editor = app.textViews["compose.textInput"]
        editor.typeText(":gif: ")
        let end = Date().addingTimeInterval(1.6)
        var colors: Set<PixelColor> = []
        repeat {
            let pixels = try Pixels(app)
            for slot in pixels.glyphs(in: editor.frame) { colors.insert(pixels.color(in: slot)) }
        } while Date() < end
        XCTAssertEqual(colors, [.green])
        XCTAssertEqual(editor.value as? String, ":gif: ")
    }

    private func openComposer(mode: String, playback: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_COMPOSE_REPLY"]
        app.launchEnvironment = ["UITEST_USE_FULL_APP": "1", "UITEST_REPLY_MODE": mode,
                                 "UITEST_COMPOSE_EMOJI_PLAYBACK": playback ? "1" : "0"]
        app.launch(isolatedFor: self)
        let open = app.buttons["replyHarness.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()
        XCTAssertTrue(app.textViews["compose.textInput"].waitForExistence(timeout: 8))
        return app
    }

    private func verifyAnimation(in editor: XCUIElement, app: XCUIApplication, count: Int = 1) throws {
        let frame = editor.frame
        let screenSize = app.frame.size
        let deadline = Date().addingTimeInterval(10)
        var seen = Array(repeating: Set<PixelColor>(), count: count)
        // On a tethered phone a screenshot can take nearly a full fixture loop.
        // Vary the sampling interval so two out-of-phase glyphs both show every color.
        let intervals = [0.04, 0.19, 0.32]
        var sample = 0
        repeat {
            let pixels = try Pixels(app, size: screenSize)
            let slots = pixels.glyphs(in: frame)
            if slots.count == count {
                for (index, slot) in slots.enumerated() { seen[index].insert(pixels.color(in: slot)) }
            }
            if seen.allSatisfy({ $0.contains(.red) && $0.contains(.blue) }) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(intervals[sample % intervals.count]))
            sample += 1
        } while Date() < deadline
        add(XCTAttachment(screenshot: app.screenshot()))
        XCTFail("Expected red and blue frames inside the editor, observed \(seen)")
    }

    func testGIFAPNGAndWebPAnimateInPlaceInTimelineAndDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TIMELINE_MEDIA", "UITEST_POST_EMOJI"]
        app.launch(isolatedFor: self)
        defer { app.terminate() }
        let toggle = app.switches["emoji.playback"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        for surface in ["Timeline", "Detail"] {
            if surface == "Detail" { app.buttons["emoji.detail"].tap() }
            let staticScreen = try baseline(in: app, below: toggle.frame.maxY)
            let slots = staticScreen.1
            let originals = slots.map { staticScreen.0.color(in: $0) }
            XCTAssertEqual(originals, [.green, .red, .green, .green, .green], surface)
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

            var colors = Array(repeating: Set<PixelColor>(), count: slots.count)
            let deadline = Date().addingTimeInterval(12)
            repeat {
                let pixels = try Pixels(app)
                for (index, slot) in slots.enumerated() { colors[index].insert(pixels.color(in: slot)) }
                if colors.dropLast().allSatisfy({ $0.contains(.red) && $0.contains(.blue) }) { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.09))
            } while Date() < deadline
            for seen in colors.dropLast() {
                XCTAssertTrue(seen.contains(.red) && seen.contains(.blue), "\(surface): \(colors), \(slots)")
            }
            XCTAssertEqual(colors.last, [.green], surface)
            // The GIF's upper right corner is transparent. The green server poster must disappear.
            let first = slots[0]
            let running = try Pixels(app)
            let movingSlots = running.glyphs(below: Int(toggle.frame.maxY))
            XCTAssertEqual(movingSlots.count, slots.count, surface)
            for (poster, moving) in zip(slots, movingSlots) {
                let position = "\(surface) poster \(poster), animated \(moving)"
                XCTAssertEqual(poster.minX, moving.minX, accuracy: 1, position)
                XCTAssertEqual(poster.minY, moving.minY, accuracy: 1, position)
                XCTAssertEqual(poster.maxX, moving.maxX, accuracy: 1, position)
                XCTAssertEqual(poster.maxY, moving.maxY, accuracy: 1, position)
            }
            XCTAssertEqual(running.at(x: Int(first.maxX) - 3, y: Int(first.minY) + 2), .other, surface)

            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            let restored = try baseline(in: app, below: toggle.frame.maxY)
            XCTAssertEqual(restored.1, slots, "\(surface) moved the text when playback changed")
            XCTAssertEqual(slots.map { restored.0.color(in: $0) }, originals)
        }
    }

    private func baseline(in app: XCUIApplication, below top: CGFloat) throws -> (Pixels, [CGRect]) {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            let pixels = try Pixels(app)
            let slots = pixels.glyphs(below: Int(top))
            if slots.count == 5 && slots.filter({ pixels.color(in: $0) == .green }).count == 4 {
                return (pixels, slots)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        let last = try Pixels(app)
        add(XCTAttachment(screenshot: app.screenshot()))
        XCTFail("Expected five posters; found \(last.glyphs(below: Int(top))). \(app.debugDescription)")
        throw NSError(domain: "postEmojiPosters", code: 1)
    }

    private enum PixelColor: Hashable { case red, green, blue, other }

    /// Locate the five actual glyphs by their saturated test colors in a one-point bitmap.
    private struct Pixels {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        @MainActor init(_ app: XCUIApplication, size: CGSize? = nil) throws {
            let image = app.screenshot().image
            let screenshot = try XCTUnwrap(image.cgImage)
            let size = size ?? app.frame.size
            width = Int(size.width)
            height = Int(size.height)
            let (w, h) = (width, height)
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let ctx = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                ctx.interpolationQuality = .none
                ctx.draw(screenshot, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            rgba = bytes
        }

        func at(x: Int, y: Int) -> PixelColor {
            let i = (y * width + x) * 4
            let (r, g, b) = (rgba[i], rgba[i + 1], rgba[i + 2])
            if r > 190 && g < 65 && b < 65 { return .red }
            if g > 200 && r < 65 && b < 65 { return .green }
            if b > 190 && r < 65 && g < 65 { return .blue }
            return .other
        }

        func color(in slot: CGRect) -> PixelColor {
            at(x: Int(slot.minX + slot.width * 0.3), y: Int(slot.midY))
        }

        func glyphs(below top: Int) -> [CGRect] {
            glyphs(in: CGRect(x: 0, y: top, width: width, height: max(0, height - top)))
        }

        func glyphs(in region: CGRect) -> [CGRect] {
            var slots: [CGRect] = []
            // Every poster has a solid left edge. Merge horizontal bands across
            // consecutive scan lines, including the APNG's transparent corner.
            let clip = region.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !clip.isEmpty else { return [] }
            let right = Int(clip.maxX)
            for y in Int(clip.minY)..<Int(clip.maxY) {
                var x = Int(clip.minX)
                while x < right {
                    let color = at(x: x, y: y)
                    let start = x
                    x += 1
                    guard color != .other else { continue }
                    while x < right && at(x: x, y: y) == color { x += 1 }
                    guard (8...34).contains(x - start) else { continue }
                    let band = CGRect(x: start, y: y, width: x - start, height: 1)
                    if let i = slots.lastIndex(where: { abs($0.minX - band.minX) <= 1 && $0.maxY == band.minY }) {
                        slots[i] = slots[i].union(band)
                    } else { slots.append(band) }
                }
            }
            return slots.filter { (8...24).contains($0.height) && $0.width > $0.height }
                .sorted { abs($0.midY - $1.midY) > 4 ? $0.midY < $1.midY : $0.minX < $1.minX }
        }
    }
}
