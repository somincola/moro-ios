//
//  ImageCache.swift
//  moro
//
//  The app's single image cache: a small async facade over SDWebImage for callers that
//  need a UIImage rather than a view (account switcher, tab avatar, search cells, emoji
//  grid, CachedAsyncImage).
//

import SDWebImage
import UIKit

/// Everything goes through SDWebImage's shared manager, so there is one memory budget,
/// one disk cache (256 MB / 7 days, see `StorageManagementStore`), one download per URL
/// however many callers ask, and decoding off the main thread. This used to be a second,
/// hand-written memory + disk cache next to SDWebImage.
///
/// Images handed out here are always a still (first frame), as before: callers draw them
/// with `Image(uiImage:)` or a plain `UIImageView`. Animated playback stays with
/// `SDWebRemoteImage`.
nonisolated public final class ImageCache: @unchecked Sendable {
    public static let shared = ImageCache()

    /// Folder of the old hand-written disk cache; removed once on launch.
    private static let legacyDirectoryName = "ImageCache"

    private var manager: SDWebImageManager { .shared }
    private var cache: SDImageCache { .shared }

    private init() {}

    private func key(for url: URL) -> String? { manager.cacheKey(for: url) }

    /// Memory only, no I/O: safe to call on the main thread for an instant, flash-free hit.
    public func image(for url: URL) -> UIImage? {
        guard let key = key(for: url) else { return nil }
        return cache.imageFromMemoryCache(forKey: key).map(Self.still)
    }

    /// Memory, then disk, then network. Concurrent requests for one URL share a download.
    /// Returns nil on failure or when the calling task is cancelled.
    public func load(from url: URL) async -> UIImage? {
        await loadReportingSource(from: url)?.image
    }

    /// Like `load(from:)`, and says whether the image had to be downloaded, so a view can
    /// fade in only what arrives from the network (cache hits appear at once).
    public func loadReportingSource(from url: URL) async -> (image: UIImage, downloaded: Bool)? {
        if let cached = image(for: url) { return (cached, false) }
        return await request(url, context: nil)
    }

    /// A thumbnail whose longest edge is at most `maxPixelSize` pixels, decoded at that
    /// size (dense grids such as the emoji picker). Cached apart from the full image; the
    /// original bytes stay on disk so other sizes don't download again.
    public func loadThumbnail(from url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let pixels = max(1, maxPixelSize.rounded(.up))
        return await request(url, context: [
            .imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: pixels, height: pixels))
        ])?.image
    }

    /// Seeds the cache (memory, and disk when `data` is given). Used by test harnesses.
    public func setImage(_ image: UIImage, for url: URL, data: Data? = nil) {
        guard let key = key(for: url) else { return }
        cache.store(image, imageData: data, forKey: key, toDisk: data != nil, completion: nil)
    }

    /// Drops these URLs from memory and disk, e.g. after the user replaced their avatar.
    public func removeImages(for urls: [URL]) {
        for url in urls {
            guard let key = key(for: url) else { continue }
            cache.removeImage(forKey: key, withCompletion: nil)
        }
    }

    /// Memory pressure: SDWebImage also does this on its own memory warning.
    public func clearMemoryCache() {
        cache.clearMemory()
    }

    /// Deletes the old hand-written cache folder left by earlier versions. Runs off the
    /// main thread; a missing folder is the normal case after the first launch.
    public static func removeLegacyDiskCache() {
        Task.detached(priority: .background) {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            else { return }
            let legacy = caches.appendingPathComponent(legacyDirectoryName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: legacy.path) else { return }
            do {
                try FileManager.default.removeItem(at: legacy)
            } catch {
                NSLog("[ImageCache] Could not remove legacy cache: \(error.localizedDescription)")
            }
        }
    }

    private func request(
        _ url: URL, context: [SDWebImageContextOption: Any]?
    ) async -> (image: UIImage, downloaded: Bool)? {
        let pending = PendingLoad()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.start(continuation) { finish in
                    // `.retryFailed`: without it SDWebImage refuses a URL for the rest of the
                    // session after one failure, and CachedAsyncImage's retries would be no-ops.
                    self.manager.loadImage(
                        with: url,
                        options: [.retryFailed, .decodeFirstFrameOnly],
                        context: context,
                        progress: nil
                    ) { image, _, _, cacheType, finished, _ in
                        guard finished else { return }
                        finish(image.map { (Self.still($0), cacheType == .none) })
                    }
                }
            }
        } onCancel: {
            pending.cancel()
        }
    }

    /// First frame of an animated image; stills pass through.
    private static func still(_ image: UIImage) -> UIImage {
        image.images?.first ?? image
    }
}

/// Bridges one SDWebImage operation to a continuation that is resumed exactly once,
/// whether the load finishes, fails, or the waiting task is cancelled first.
nonisolated private final class PendingLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(image: UIImage, downloaded: Bool)?, Never>?
    private var operation: SDWebImageOperation?
    private var isCancelled = false

    func start(
        _ continuation: CheckedContinuation<(image: UIImage, downloaded: Bool)?, Never>,
        load: (@escaping ((image: UIImage, downloaded: Bool)?) -> Void) -> SDWebImageOperation?
    ) {
        let cancelledEarly = lock.withLock {
            if isCancelled { return true }
            self.continuation = continuation
            return false
        }
        if cancelledEarly {
            continuation.resume(returning: nil)
            return
        }
        let operation = load { [weak self] result in self?.finish(result) }
        let cancelNow = lock.withLock {
            self.operation = operation
            return isCancelled
        }
        if cancelNow { operation?.cancel() }
    }

    func cancel() {
        let operation = lock.withLock {
            isCancelled = true
            return self.operation
        }
        operation?.cancel()
        finish(nil)
    }

    private func finish(_ result: (image: UIImage, downloaded: Bool)?) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: result)
    }
}
