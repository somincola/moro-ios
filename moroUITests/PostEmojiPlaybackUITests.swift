import XCTest
import UIKit

@MainActor
final class PostEmojiPlaybackUITests: XCTestCase {
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

        @MainActor init(_ app: XCUIApplication) throws {
            let image = app.screenshot().image
            let screenshot = try XCTUnwrap(image.cgImage)
            width = Int(app.frame.width)
            height = Int(app.frame.height)
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
            var slots: [CGRect] = []
            // Every poster has a solid left edge. Merge horizontal bands across
            // consecutive scan lines, including the APNG's transparent corner.
            for y in max(0, top)..<height {
                var x = 0
                while x < width {
                    let color = at(x: x, y: y)
                    let start = x
                    x += 1
                    guard color != .other else { continue }
                    while x < width && at(x: x, y: y) == color { x += 1 }
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
