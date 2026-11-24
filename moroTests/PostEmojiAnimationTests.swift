import SDWebImage
import Testing
import UIKit
import XCTest
@testable import moro

@MainActor
struct PostEmojiAnimationTests {
    // The second frame changes just one pixel; this APNG is authored for three loops.
    private let finiteAPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAACGFjVEwAAAACAAAAA2qEwsoAAAAaZmNUTAAAAAAAAAAEAAAAAgAAAAAAAAAAAAEABQAAftSQLgAAABJJREFUeJxj+M/A8B8ZM6ALAAAPIQ/xBDfGnwAAABpmY1RMAAAAAQAAAAEAAAABAAAAAwAAAAEAAQAFAAD1xfCMAAAAEWZkQVQAAAACeJxjYGD4/x8AAwIB//V7pdcAAAAASUVORK5CYII=")!
    @Test func recognizesAnimationBytesAndPreservesFrameTimingAcrossFormats() throws {
        for (name, data) in PostEmojiPlaybackFixture.originals {
            let animation = try #require(PostEmojiAnimation.decode(data, pixelSize: 16), "Missing animation for \(name)")
            #expect(animation.frames.count == 2)
            #expect(abs(animation.duration - 0.7) < 0.002)
            #expect(abs(animation.frameStarts[1] - 0.23 / 0.7) < 0.002)
            #expect(animation.loops == 0)
            #expect(animation.frames.allSatisfy { $0.width == 16 && $0.height == 10 })
        }
    }

    @Test func staticPNGAndUnreadableDataKeepThePoster() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { _ in }
        #expect(PostEmojiAnimation.decode(try #require(image.pngData()), pixelSize: 24) == nil)
        #expect(PostEmojiAnimation.decode(Data("invalid".utf8), pixelSize: 24) == nil)
    }

    @Test func deltaAPNGKeepsItsCanvasAndPaintsOnlyTheChangedPixel() throws {
        // The second encoded frame contains just one blue pixel at (3, 1) on a 4×2 red canvas.
        let animation = try #require(PostEmojiAnimation.decode(finiteAPNG, pixelSize: 4))
        #expect(animation.loops == 3)
        let frame = animation.frames[1]
        #expect(frame.width == 4 && frame.height == 2)
        var pixels = [UInt8](repeating: 0, count: 32)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 4, height: 2,
                bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(frame, in: CGRect(x: 0, y: 0, width: 4, height: 2))
        }
        #expect(Array(pixels.prefix(28)) == Array(repeating: [UInt8(255), 0, 0, 255], count: 7).flatMap { $0 })
        #expect(Array(pixels.suffix(4)) == [0, 0, 255, 255])
    }

    @Test func repeatedOccurrencesShareDecodedFramesEvenWithAMisleadingExtension() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try PostEmojiPlaybackFixture.originals[0].data.write(to: url)
        let store = PostEmojiAnimationStore()
        async let first = store.animation(for: url, pixelSize: 32)
        async let second = store.animation(for: url, pixelSize: 32)
        let (a, b) = await (first, second)
        #expect(a != nil && a === b)
    }

    @Test func aRetainedLayerRestoresItsLoopWhenItsSceneBecomesActive() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = InlineEmojiLayerHost(frame: CGRect(x: 0, y: 0, width: 80, height: 24))
        window.addSubview(host)
        let source = try #require(PostEmojiPlaybackFixture.post.emojis?.first)
        let marker = InlineEmojiMarker(index: 0, url: source.url)
        let slot = InlineEmojiSlot(marker: marker, frame: host.bounds)
        let animation = try #require(PostEmojiAnimation.decode(PostEmojiPlaybackFixture.originals[0].data, pixelSize: 24))
        host.update(slots: [slot], playing: [marker: animation])
        let layer = try #require(host.layer.sublayers?.first)
        let initial = try #require(layer.animation(forKey: "postEmoji"))
        layer.removeAllAnimations()
        layer.contents = nil
        layer.removeFromSuperlayer()
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        #expect(layer.superlayer === host.layer)
        #expect(layer.contents as AnyObject? === animation.frames.last)
        let resumed = try #require(layer.animation(forKey: "postEmoji"))
        #expect(resumed.beginTime == initial.beginTime && resumed.repeatCount == .infinity)
        host.update(slots: [], playing: [:])
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        #expect(host.layer.sublayers?.isEmpty != false)
    }

    @Test func refreshingAnEndedFiniteEmojiKeepsItsFinalFrame() throws {
        let animation = try #require(PostEmojiAnimation.decode(finiteAPNG, pixelSize: 4))
        let host = InlineEmojiLayerHost()
        let marker = InlineEmojiMarker(index: 0, url: URL(fileURLWithPath: "/finite.png"))
        let slot = InlineEmojiSlot(marker: marker, frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        host.update(slots: [slot], playing: [marker: animation])
        let layer = try #require(host.layer.sublayers?.first)
        let start = try #require(layer.animation(forKey: "postEmoji")).beginTime
        layer.speed = 0
        layer.timeOffset = start + animation.duration * Double(animation.loops) + 1
        layer.removeAllAnimations()
        host.update(slots: [slot], playing: [marker: animation])
        #expect(layer.animation(forKey: "postEmoji") == nil)
        #expect(layer.contents as AnyObject? === animation.frames.last)
    }

    @Test func staticPNGMarksURLAsKnownStill() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { _ in }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try #require(image.pngData()).write(to: url)
        let store = PostEmojiAnimationStore()
        #expect(!store.isKnownStill(for: url))
        #expect(await store.animation(for: url, pixelSize: 24) == nil)
        #expect(store.isKnownStill(for: url))
    }

    @Test func playbackPolicySkipsViewportClipOnNormalHeightsAndDefersOnlyUncachedDecodeDuringScroll() {
        #expect(!PostEmojiPlaybackPolicy.shouldClipToScrollView(contentHeight: 200, isScrolling: false))
        #expect(!PostEmojiPlaybackPolicy.shouldClipToScrollView(contentHeight: 200, isScrolling: true))
        #expect(PostEmojiPlaybackPolicy.shouldClipToScrollView(contentHeight: 1200, isScrolling: false))
        #expect(!PostEmojiPlaybackPolicy.shouldClipToScrollView(contentHeight: 1200, isScrolling: true))

        #expect(PostEmojiPlaybackPolicy.shouldDecodeUncached(hasUncached: true, isScrolling: false))
        #expect(!PostEmojiPlaybackPolicy.shouldDecodeUncached(hasUncached: true, isScrolling: true))
        #expect(!PostEmojiPlaybackPolicy.shouldDecodeUncached(hasUncached: false, isScrolling: false))
    }
}

// XCTest runs this warm-cache case separately from Swift Testing's app-wide memory warnings.
final class PostEmojiPickerCacheTests: XCTestCase {
    @MainActor
    func testPickerOriginalCanStartAnAnimationWithoutAnotherDownload() async throws {
        let data = PostEmojiPlaybackFixture.originals[0].data
        let image = try XCTUnwrap(SDAnimatedImage(data: data))
        // A missing file URL makes a cache miss fail immediately.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).gif")
        let cache = SDImageCache.shared
        await cache.store(image, imageData: data, forKey: url.absoluteString, toDisk: false)
        defer { cache.removeImageFromMemory(forKey: url.absoluteString) }

        let store = PostEmojiAnimationStore()
        let result = await store.animation(for: url, pixelSize: 48)
        let animation = try XCTUnwrap(result)
        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertTrue(store.cachedAnimation(for: url, pixelSize: 48) === animation)
    }
}
