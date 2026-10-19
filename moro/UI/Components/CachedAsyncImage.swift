//
//  CachedAsyncImage.swift
//  moro
//
//  Async image view over the shared ImageCache (SDWebImage), with retry and blur hash.
//

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

/// An AsyncImage backed by the shared ImageCache, with retry and blur hash support
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

        let configuration = configuration
        loadTask = Task {
            // Disk then network through the shared SDWebImage pipeline: one download per URL
            // however many views ask, disk read and decode off the main thread. Retries live
            // inside this task, so they stop when the view goes away or its URL changes.
            var attempt = 0
            while !Task.isCancelled {
                if let loaded = await ImageCache.shared.loadReportingSource(from: url) {
                    guard !Task.isCancelled else { return }
                    // Fade in downloads only; a disk hit appears at once, as before.
                    if loaded.downloaded {
                        withAnimation(.easeIn(duration: 0.2)) {
                            phase = .success(Image(uiImage: loaded.image))
                        }
                    } else {
                        phase = .success(Image(uiImage: loaded.image))
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                guard configuration.retryOnFailure, attempt < configuration.maxRetryAttempts else {
                    phase = .failure(URLError(.cannotLoadFromNetwork))
                    return
                }
                attempt += 1
                retryCount = attempt
                do {
                    try await Task.sleep(for: .seconds(configuration.retryDelay))
                } catch {
                    return
                }
            }
        }
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
