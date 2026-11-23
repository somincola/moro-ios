import Testing
import UIKit
@testable import moro

@MainActor
struct PostEmojiAnimationTests {
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
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAACGFjVEwAAAACAAAAA2qEwsoAAAAaZmNUTAAAAAAAAAAEAAAAAgAAAAAAAAAAAAEABQAAftSQLgAAABJJREFUeJxj+M/A8B8ZM6ALAAAPIQ/xBDfGnwAAABpmY1RMAAAAAQAAAAEAAAABAAAAAwAAAAEAAQAFAAD1xfCMAAAAEWZkQVQAAAACeJxjYGD4/x8AAwIB//V7pdcAAAAASUVORK5CYII=")!
        let animation = try #require(PostEmojiAnimation.decode(data, pixelSize: 4))
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
}
