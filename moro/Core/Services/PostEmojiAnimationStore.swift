import Foundation
import ImageIO

/// Composited thumbnail frames shared by every visible occurrence of an original.
nonisolated final class PostEmojiAnimation: Sendable {
    let frames: [CGImage]
    let frameStarts: [Double]
    let duration: TimeInterval
    let loops: Int
    let byteCount: Int

    private init(frames: [CGImage], starts: [Double], duration: TimeInterval, loops: Int, bytes: Int) {
        self.frames = frames
        self.frameStarts = starts.map { $0 / duration }
        self.duration = duration
        self.loops = loops
        self.byteCount = bytes
    }

    static func decode(_ data: Data, pixelSize: Int) -> PostEmojiAnimation? {
        guard pixelSize > 0, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard (2...AvatarAnimationLimits.maximumFrames).contains(count),
              let first = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = first[kCGImagePropertyPixelWidth] as? Int,
              let height = first[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) <= AvatarAnimationLimits.maximumCanvasSide else { return nil }

        // ImageIO identifies the container from its bytes. In particular, an APNG is
        // normally served as image/png and its original and poster can have the same URL.
        let formats = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime, kCGImagePropertyGIFLoopCount),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime, kCGImagePropertyAPNGLoopCount),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime, kCGImagePropertyWebPLoopCount),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime, kCGImagePropertyHEICSLoopCount),
        ]
        guard let (container, unclamped, delay, loopKey) = formats.first(where: { first[$0.0] != nil }) else { return nil }
        let metadata = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let loops = (metadata?[container] as? [CFString: Any])?[loopKey] as? Int ?? 1
        // Longer animations use smaller thumbnails to stay inside the same decoded budget.
        let maxSide = min(pixelSize, Int(sqrt(Double(2 * 1024 * 1024 / (count * 4)))))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxSide,
                                        kCGImageSourceShouldCacheImmediately: true]
        var frames: [CGImage] = [], starts: [Double] = []
        var duration: TimeInterval = 0
        var bytes = 0
        for index in 0..<count {
            guard !Task.isCancelled,
                  let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let timing = properties?[container] as? [CFString: Any]
            let seconds = (timing?[unclamped] ?? timing?[delay]) as? Double ?? 0
            starts.append(duration)
            duration += seconds >= 0.011 && seconds.isFinite ? seconds : 0.1
            frames.append(frame)
            bytes += frame.bytesPerRow * frame.height
        }
        return PostEmojiAnimation(frames: frames, starts: starts, duration: duration, loops: loops, bytes: bytes)
    }
}

actor PostEmojiAnimationStore {
    static let shared = PostEmojiAnimationStore()
    private let animations = NSCache<NSString, PostEmojiAnimation>()
    private let stills = NSCache<NSURL, NSNumber>()

    init() {
        animations.totalCostLimit = 12 * 1024 * 1024
        stills.countLimit = 1200
    }

    func animation(for url: URL, pixelSize: Int) async -> PostEmojiAnimation? {
        let key = "\(pixelSize)|\(url.absoluteString)" as NSString
        if let cached = animations.object(forKey: key) { return cached }
        guard stills.object(forKey: url as NSURL) == nil,
              let data = try? await AvatarAnimationDataStore.shared.data(for: url), !Task.isCancelled else { return nil }
        // Other occurrences can finish decoding while this caller waits for shared bytes.
        if let cached = animations.object(forKey: key) { return cached }
        guard stills.object(forKey: url as NSURL) == nil else { return nil }
        if let animation = PostEmojiAnimation.decode(data, pixelSize: pixelSize) {
            animations.setObject(animation, forKey: key, cost: animation.byteCount)
            return animation
        }
        if !Task.isCancelled { stills.setObject(true, forKey: url as NSURL) }
        return nil
    }
}
