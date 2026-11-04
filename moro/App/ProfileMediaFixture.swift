#if DEBUG
import ImageIO
import SDWebImage
import UIKit
import UniformTypeIdentifiers

/// Offline animated profile media, shared by the real-screen harness and renderer tests.
@MainActor
enum ProfileMediaFixture {
    static let avatarURL = URL(string: "https://profile-media-fixture.invalid/avatar.gif")!
    static let staticAvatarURL = URL(string: "https://profile-media-fixture.invalid/avatar.png")!
    static let headerURL = URL(string: "https://profile-media-fixture.invalid/header.gif")!
    static let staticHeaderURL = URL(string: "https://profile-media-fixture.invalid/header.png")!

    static func prepare() {
        for (animatedURL, staticURL, size) in [
            (avatarURL, staticAvatarURL, CGSize(width: 240, height: 240)),
            (headerURL, staticHeaderURL, CGSize(width: 600, height: 240)),
        ] {
            let data = gifData(size: size)
            let image = SDAnimatedImage(data: data)!
            SDImageCache.shared.store(image, imageData: data, forKey: animatedURL.absoluteString, toDisk: false)
            let still = UIImage(cgImage: image.cgImage!)
            SDImageCache.shared.store(still, forKey: staticURL.absoluteString, toDisk: false)
            for side: CGFloat in [228, 2000, 8192] {
                let context: [SDWebImageContextOption: Any] = [
                    .imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: side, height: side))
                ]
                let key = SDWebImageManager.shared.cacheKey(for: animatedURL, context: context)!
                SDImageCache.shared.store(image, forKey: key, toDisk: false)
                let staticKey = SDWebImageManager.shared.cacheKey(for: staticURL, context: context)!
                SDImageCache.shared.store(still, forKey: staticKey, toDisk: false)
            }
        }
    }

    static func gifData(size: CGSize = CGSize(width: 80, height: 80), frameDuration: TimeInterval = 0.4) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil)!
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        for color in [UIColor.systemIndigo, UIColor.systemTeal] {
            let frame = UIGraphicsImageRenderer(size: size, format: format).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.35, y: size.height * 0.35,
                    width: size.width * 0.3, height: size.height * 0.3))
            }
            CGImageDestinationAddImage(destination, frame.cgImage!, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: frameDuration]
            ] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
#endif
