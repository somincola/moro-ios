import ImageIO
import SDWebImage

/// SDWebImage 5.21's static ImageIO coder doesn't apply its byte-limit option.
/// Calculate a thumbnail size before decoding instead of allocating a full bitmap
/// and shrinking it afterwards. This coder is local to the fullscreen viewer.
final class ImagePreviewImageCoder: NSObject, SDImageCoder, @unchecked Sendable {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    nonisolated static let shared = ImagePreviewImageCoder()
    nonisolated static let maximumPixelCount: Double = 8 * 1024 * 1024

    nonisolated override init() { super.init() }

    nonisolated func canDecode(from data: Data?) -> Bool {
        SDImageCodersManager.shared.canDecode(from: data)
    }

    nonisolated func decodedImage(with data: Data?, options: [SDImageCoderOption: Any]? = nil) -> UIImage? {
        guard let data else { return nil }
        var boundedOptions = options ?? [:]
        // A conservative fallback also covers formats for which ImageIO cannot read dimensions.
        var longestEdge = sqrt(Self.maximumPixelCount)
        if let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width > 0, height > 0, width.isFinite, height.isFinite {
            let frames = max(CGImageSourceGetCount(source), 1)
            let factor = min(1, sqrt(Self.maximumPixelCount / Double(frames) / (width * height)))
            longestEdge = min(max(width, height) * factor, 16384)
        }
        boundedOptions[.decodeThumbnailPixelSize] = NSValue(cgSize: CGSize(width: floor(longestEdge), height: floor(longestEdge)))
        boundedOptions[.decodePreserveAspectRatio] = true
        boundedOptions[.decodeUseLazyDecoding] = false
        return SDImageCodersManager.shared.decodedImage(with: data, options: boundedOptions)
    }

    nonisolated func canEncode(to format: SDImageFormat) -> Bool {
        SDImageCodersManager.shared.canEncode(to: format)
    }

    nonisolated func encodedData(with image: UIImage?, format: SDImageFormat, options: [SDImageCoderOption: Any]? = nil) -> Data? {
        SDImageCodersManager.shared.encodedData(with: image, format: format, options: options)
    }
}
