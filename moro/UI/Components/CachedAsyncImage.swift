//
//  CachedAsyncImage.swift
//  moro
//
//  Enhanced async image view with caching, retry logic, and blur hash support.
//

import Combine
import CryptoKit
import ImageIO
import SwiftUI

/// Configuration for CachedAsyncImage behavior
public struct ImageCacheConfiguration {
    /// Whether to automatically retry failed downloads
    public var retryOnFailure: Bool = true

    /// Number of retry attempts
    public var maxRetryAttempts: Int = 2

    /// Delay between retries (in seconds)
    public var retryDelay: TimeInterval = 1.0

    /// Whether to continue downloads in background
    public var continueInBackground: Bool = true

    /// Global configuration
    public static var `default` = ImageCacheConfiguration()
}

/// An improved AsyncImage with disk caching, retry logic, and blur hash support
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {

    private let url: URL?
    private let blurhash: String?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let configuration: ImageCacheConfiguration

    @State private var phase: AsyncImagePhase = .empty
    @State private var retryCount: Int = 0
    @State private var loadTask: Task<Void, Never>?

    public init(
        url: URL?,
        blurhash: String? = nil,
        configuration: ImageCacheConfiguration = .default,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.blurhash = blurhash
        self.configuration = configuration
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        contentView
            .onAppear { loadImage() }
            .onChange(of: url) { oldValue, newValue in
                if oldValue != newValue {
                    retryCount = 0
                    loadImage()
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch phase {
        case .empty:
            placeholderView
        case .success(let image):
            content(image)
        case .failure:
            placeholderView
                .overlay(alignment: .center) {
                    if configuration.retryOnFailure && retryCount < configuration.maxRetryAttempts {
                        ProgressView()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
        @unknown default:
            placeholderView
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        Group {
            if let blurhash = blurhash, !blurhash.isEmpty {
                BlurHashPlaceholder(blurhash: blurhash)
            } else {
                placeholder()
            }
        }
    }

    private func loadImage() {
        loadTask?.cancel()

        guard let url = url else {
            phase = .empty
            return
        }

        // Memory cache: an NSCache read, no I/O — safe to resolve synchronously for an
        // instant hit with no flash.
        if let cachedImage = ImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cachedImage))
            return
        }

        loadTask = Task {
            // Disk-cache read + decode OFF the main thread. This used to run synchronously
            // in `.onAppear` (Data(contentsOf:) + UIImage(data:)), stalling the main thread
            // for every image cell that appeared — a per-cell hitch that compounded into a
            // freeze on the profile feed (far worse on the Simulator's software pipeline).
            let diskImage = await Task.detached(priority: .userInitiated) {
                ImageCache.shared.imageFromDisk(for: url)
            }.value

            if let diskImage {
                if !Task.isCancelled {
                    await MainActor.run { phase = .success(Image(uiImage: diskImage)) }
                }
                return
            }

            do {
                let image = try await downloadImage(from: url)

                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.easeIn(duration: 0.2)) {
                            phase = .success(Image(uiImage: image))
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        if configuration.retryOnFailure
                            && retryCount < configuration.maxRetryAttempts
                        {
                            retryCount += 1
                            // Schedule retry
                            Task {
                                try? await Task.sleep(
                                    nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                                loadImage()
                            }
                        } else {
                            phase = .failure(error)
                        }
                    }
                }
            }
        }
    }

    private func downloadImage(from url: URL) async throws -> UIImage {
        let generation = ImageCache.shared.writeGeneration
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode
        else {
            throw URLError(.badServerResponse)
        }

        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Cache the image
        ImageCache.shared.setImage(image, for: url, data: data, generation: generation)

        return image
    }
}

// MARK: - Blur Hash Placeholder

private struct BlurHashPlaceholder: View {
    let blurhash: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .onAppear {
            // Decode blurhash on background thread
            Task.detached(priority: .background) {
                if let decoded = BlurHashDecoder.decode(
                    blurhash, size: CGSize(width: 32, height: 32))
                {
                    await MainActor.run {
                        self.image = decoded
                    }
                }
            }
        }
    }
}

// MARK: - Image Cache

/// Simple in-memory and disk image cache
nonisolated public final class ImageCache: @unchecked Sendable {
    public static let shared = ImageCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    /// Separate cache for viewer-sized downsampled images, so re-opening / swiping
    /// doesn't re-read disk and re-run ImageIO, and so it can't collide with the
    /// full-size entry for the same URL.
    private let downsampledCache = NSCache<NSURL, UIImage>()
    /// Small, size-keyed thumbnails used by dense grids such as the emoji picker.
    /// Keeping this separate prevents full-size media and tiny icons from evicting
    /// each other from the general image cache.
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let disk = ImageDiskCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ImageCache", isDirectory: true))

    public var writeGeneration: UUID { disk.writeGeneration }

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50 MB

        downsampledCache.countLimit = 6

        thumbnailCache.countLimit = 300
        thumbnailCache.totalCostLimit = 24 * 1024 * 1024


    }

    public func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    public func imageFromDisk(for url: URL) -> UIImage? {
        guard let data = disk.data(for: url), let image = UIImage(data: data) else { return nil }

        // Also add to memory cache
        memoryCache.setObject(image, forKey: url as NSURL, cost: Self.memoryCost(of: image))
        return image
    }

    /// Decoded-bitmap byte size, so NSCache's `totalCostLimit` (50 MB) can actually evict.
    /// Without a cost every entry counts as 0 and the limit never fires.
    private static func memoryCost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    public func setImage(_ image: UIImage, for url: URL, data: Data? = nil, generation: UUID? = nil) {
        let expected = generation ?? writeGeneration
        guard expected == writeGeneration else { return }
        memoryCache.setObject(image, forKey: url as NSURL, cost: Self.memoryCost(of: image))
        if let data { disk.store(data, for: url, generation: expected) }
    }

    /// Memory -> disk -> network load for callers that aren't SwiftUI views
    /// (e.g. UIKit cells). Mirrors CachedAsyncImage's own load path so everything
    /// shares one cache.
    public func load(from url: URL) async -> UIImage? {
        let generation = writeGeneration
        if let cached = image(for: url) { return cached }
        if let disk = imageFromDisk(for: url) { return disk }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
            let image = UIImage(data: data)
        else { return nil }

        setImage(image, for: url, data: data, generation: generation)
        return image
    }

    /// Loads `url` downsampled so its longest edge is at most `maxPixelSize` pixels.
    /// The full-screen viewer uses this so a high-megapixel original never becomes a
    /// giant in-memory bitmap (the cause of the viewer freeze + runaway memory). The
    /// raw bytes reuse the on-disk cache; the decoded thumbnail is deliberately NOT
    /// stored in the memory cache (it would collide with the full-size entry for the
    /// same URL).
    public func loadDownsampled(from url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        if let cached = downsampledCache.object(forKey: url as NSURL) {
            return cached
        }

        let generation = writeGeneration
        let data: Data
        if let onDisk = disk.data(for: url), !onDisk.isEmpty {
            data = onDisk
        } else {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (downloaded, response) = try? await URLSession.shared.data(for: request),
                let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode
            else { return nil }
            data = downloaded
            disk.store(downloaded, for: url, generation: generation)
        }
        guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        if generation == writeGeneration { downsampledCache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Loads a compact thumbnail for dense icon grids. The cache key includes the
    /// requested pixel size, and ImageIO decodes only the pixels the grid needs.
    public func loadThumbnail(from url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let normalizedPixelSize = max(1, maxPixelSize.rounded(.up))
        let cacheKey = "\(url.absoluteString)#\(Int(normalizedPixelSize))" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        let generation = writeGeneration
        let data: Data
        if let onDisk = disk.data(for: url), !onDisk.isEmpty {
            data = onDisk
        } else {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (downloaded, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                return nil
            }
            data = downloaded
            disk.store(downloaded, for: url, generation: generation)
        }

        guard !Task.isCancelled,
              let image = Self.downsample(data: data, maxPixelSize: normalizedPixelSize) else {
            return nil
        }
        if generation == writeGeneration { thumbnailCache.setObject(image, forKey: cacheKey, cost: Self.memoryCost(of: image)) }
        return image
    }

    nonisolated private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maxPixelSize)),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
        downsampledCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    public func diskSize() async -> Int64 { await disk.size() }

    public func clearDiskCache() {
        Task { try? await disk.clear() }
    }

    public func clearAllAndWait() async throws {
        try await disk.clear()
        clearMemoryCache()
    }

    public func clearAll() {
        clearMemoryCache()
        clearDiskCache()
    }

}

// MARK: - BlurHash Decoder

/// Minimal BlurHash decoder for generating placeholder images
private enum BlurHashDecoder {
    nonisolated static func decode(_ blurhash: String, size: CGSize, punch: Float = 1.0) -> UIImage? {
        guard blurhash.count >= 6 else { return nil }

        let sizeFlag = decode83(String(blurhash[blurhash.startIndex]))
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1

        let quantisedMaximumValue = decode83(
            String(blurhash[blurhash.index(blurhash.startIndex, offsetBy: 1)]))
        let maximumValue = Float(quantisedMaximumValue + 1) / 166

        guard blurhash.count == 4 + 2 * numX * numY else { return nil }

        var colors: [(Float, Float, Float)] = []

        for i in 0..<numX * numY {
            if i == 0 {
                let value = decode83(
                    String(
                        blurhash[
                            blurhash.index(
                                blurhash.startIndex, offsetBy: 2)..<blurhash.index(
                                    blurhash.startIndex, offsetBy: 6)]))
                colors.append(decodeDC(value))
            } else {
                let startIndex = blurhash.index(blurhash.startIndex, offsetBy: 4 + i * 2)
                let endIndex = blurhash.index(startIndex, offsetBy: 2)
                let value = decode83(String(blurhash[startIndex..<endIndex]))
                colors.append(decodeAC(value, maximumValue * punch))
            }
        }

        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0

                for j in 0..<numY {
                    for i in 0..<numX {
                        let basis =
                            cos(Float.pi * Float(x) * Float(i) / Float(width))
                            * cos(Float.pi * Float(y) * Float(j) / Float(height))
                        let color = colors[i + j * numX]
                        r += color.0 * basis
                        g += color.1 * basis
                        b += color.2 * basis
                    }
                }

                let intR = UInt8(max(0, min(255, linearToSrgb(r) * 255 + 0.5)))
                let intG = UInt8(max(0, min(255, linearToSrgb(g) * 255 + 0.5)))
                let intB = UInt8(max(0, min(255, linearToSrgb(b) * 255 + 0.5)))

                let offset = (y * bytesPerRow) + (x * 4)
                pixels[offset] = intR
                pixels[offset + 1] = intG
                pixels[offset + 2] = intB
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels)
        guard let mutableData = CFDataCreateMutableCopy(kCFAllocatorDefault, data.count, data as CFData),
              let provider = CGDataProvider(data: mutableData) else { return nil }

        guard
            let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else { return nil }

        return UIImage(cgImage: cgImage)
    }

    nonisolated private static let alphabet =
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"

    nonisolated private static func decode83(_ str: String) -> Int {
        var value = 0
        for char in str {
            if let digit = alphabet.firstIndex(of: char) {
                value = value * 83 + alphabet.distance(from: alphabet.startIndex, to: digit)
            }
        }
        return value
    }

    nonisolated private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        let intR = value >> 16
        let intG = (value >> 8) & 255
        let intB = value & 255
        return (
            srgbToLinear(Float(intR) / 255), srgbToLinear(Float(intG) / 255),
            srgbToLinear(Float(intB) / 255)
        )
    }

    nonisolated private static func decodeAC(_ value: Int, _ maximumValue: Float) -> (Float, Float, Float) {
        let quantR = value / (19 * 19)
        let quantG = (value / 19) % 19
        let quantB = value % 19
        return (
            signPow((Float(quantR) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantG) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantB) - 9) / 9, 2) * maximumValue
        )
    }

    nonisolated private static func signPow(_ value: Float, _ exp: Float) -> Float {
        copysign(pow(abs(value), exp), value)
    }

    nonisolated private static func srgbToLinear(_ value: Float) -> Float {
        if value <= 0.04045 {
            return value / 12.92
        } else {
            return pow((value + 0.055) / 1.055, 2.4)
        }
    }

    nonisolated private static func linearToSrgb(_ value: Float) -> Float {
        if value <= 0.0031308 {
            return value * 12.92
        } else {
            return pow(value, 1 / 2.4) * 1.055 - 0.055
        }
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == Color {
    public init(
        url: URL?,
        blurhash: String? = nil,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url, blurhash: blurhash, content: content, placeholder: { Color.gray.opacity(0.2) }
        )
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    public init(url: URL?, blurhash: String? = nil) {
        self.init(
            url: url, blurhash: blurhash, content: { $0.resizable() },
            placeholder: { Color.gray.opacity(0.2) })
    }
}
