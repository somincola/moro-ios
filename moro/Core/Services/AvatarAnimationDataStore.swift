import Foundation
import SDWebImage

nonisolated enum AvatarAnimationLimits {
    static let maximumFileBytes = 2 * 1024 * 1024
    static let maximumCanvasSide = 1024
    static let maximumFrames = 200
    static let maximumContexts = 8
    static let dataBudget = 4 * 1024 * 1024
    static let frameBudget = 4 * 1024 * 1024
    static let frameReservation = 512 * 1024
    static let frameBufferBytes: UInt = 300 * 1024
    static let warmCount = 2
    static let warmBudget = 2 * 1024 * 1024
    static let warmLifetime: TimeInterval = 2

    static func pixelSize(for points: CGFloat, scale: CGFloat) -> Int {
        let pixels = points * scale
        return pixels <= 96 ? 96 : pixels <= 128 ? 128 : 160
    }
}

/// Stores compressed originals only. Animated UIImage/provider objects never enter the
/// shared SDImageCache; their only owner outside a visible view is the bounded avatar pool.
actor AvatarAnimationDataStore {
    static let shared = AvatarAnimationDataStore()
    private let cache: SDImageCache
    private struct Request {
        let id: UUID
        let task: Task<Data, Error>
        var consumers: Set<UUID>
    }
    private var requests: [URL: Request] = [:]
    private var runningDownloads = 0
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []

    init(namespace: String = "timeline-animated-avatars") {
        let config = SDImageCacheConfig()
        config.shouldCacheImagesInMemory = false
        config.maxDiskSize = 64 * 1024 * 1024
        config.maxDiskAge = 7 * 24 * 60 * 60
        cache = SDImageCache(namespace: namespace, diskCacheDirectory: nil, config: config)
    }

    func data(for url: URL) async throws -> Data {
        try Task.checkCancellation()
        if url.isFileURL {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? .max) <= AvatarAnimationLimits.maximumFileBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
        if let data = cache.diskImageData(forKey: url.absoluteString),
           data.count <= AvatarAnimationLimits.maximumFileBytes { return data }
        let consumer = UUID()
        let request: Request
        if var existing = requests[url] {
            existing.consumers.insert(consumer)
            requests[url] = existing
            request = existing
        } else {
            request = Request(id: UUID(), task: Task { try await download(url) }, consumers: [consumer])
            requests[url] = request
        }
        return try await withTaskCancellationHandler {
            defer { release(url, requestID: request.id, consumer: consumer) }
            let data = try await request.task.value
            try Task.checkCancellation()
            return data
        } onCancel: {
            Task { await self.release(url, requestID: request.id, consumer: consumer) }
        }
    }

    private func release(_ url: URL, requestID: UUID, consumer: UUID) {
        guard var request = requests[url], request.id == requestID else { return }
        request.consumers.remove(consumer)
        if request.consumers.isEmpty {
            request.task.cancel()
            requests[url] = nil
        } else { requests[url] = request }
    }

    private func download(_ url: URL) async throws -> Data {
        if runningDownloads < 2 { runningDownloads += 1 }
        else { await withCheckedContinuation { downloadWaiters.append($0) } }
        defer {
            if downloadWaiters.isEmpty { runningDownloads -= 1 }
            else { downloadWaiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        let result = try await BoundedAvatarDownload.load(url)
        try Task.checkCancellation()
        if result.cacheable {
            cache.storeImageData(toDisk: result.data, forKey: url.absoluteString)
            await cache.deleteOldFiles()
        }
        return result.data
    }
}

/// URLSession delegate callbacks are serialized, and cancellation may arrive on any thread.
/// The lock protects the continuation, transfer buffer and session across that boundary.
nonisolated final class BoundedAvatarDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Result {
        let data: Data
        let cacheable: Bool
    }
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result, Error>?
    private var session: URLSession?
    private var data = Data()
    private var cacheable = true
    private var finished = false

    static func load(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) async throws -> Result {
        let download = BoundedAvatarDownload()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { download.start(url, configuration: configuration, continuation: $0) }
        } onCancel: { download.finish(.failure(CancellationError())) }
    }

    private func start(_ url: URL, configuration: URLSessionConfiguration, continuation: CheckedContinuation<Result, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        lock.unlock()
        session.dataTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.expectedContentLength <= AvatarAnimationLimits.maximumFileBytes else {
            completionHandler(.cancel)
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        lock.withLock {
            cacheable = !(response.value(forHTTPHeaderField: "Cache-Control") ?? "")
                .lowercased().contains("no-store")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let accepted = lock.withLock {
            guard !finished, data.count + chunk.count <= AvatarAnimationLimits.maximumFileBytes else { return false }
            data.append(chunk)
            return true
        }
        if !accepted { finish(.failure(URLError(.dataLengthExceedsMaximum))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else {
            let result = lock.withLock { Result(data: data, cacheable: cacheable) }
            finish(.success(result))
        }
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        let state = lock.withLock { () -> (CheckedContinuation<Result, Error>?, URLSession?) in
            guard !finished else { return (nil, nil) }
            finished = true
            let state = (continuation, session)
            continuation = nil
            session = nil
            data = Data()
            return state
        }
        state.1?.invalidateAndCancel()
        state.0?.resume(with: result)
    }
}
