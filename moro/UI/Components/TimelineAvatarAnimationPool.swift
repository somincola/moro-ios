import ImageIO
import Observation
import SDWebImage
import UIKit

nonisolated struct PreparedAvatarAnimation {
    let image: SDAnimatedImage
    let dataBytes: Int
    let warmCost: Int
}

/// Serializes initial parsing/first-frame work away from the main actor. Subsequent frames
/// use SDWebImage's bounded frame pool; they are not published through SwiftUI state.
actor AvatarAnimationDecoder {
    static let shared = AvatarAnimationDecoder()

    func prepare(_ data: Data, pixelSize: Int) -> PreparedAvatarAnimation? {
        guard data.count <= AvatarAnimationLimits.maximumFileBytes else { return nil }
        var logicalCanvasBytes = 0
        if data.count >= 10, data.prefix(3) == Data("GIF".utf8) {
            let width = Int(data[6]) | Int(data[7]) << 8
            let height = Int(data[8]) | Int(data[9]) << 8
            guard width > 0, height > 0, width <= AvatarAnimationLimits.maximumCanvasSide,
                  height <= AvatarAnimationLimits.maximumCanvasSide else { return nil }
            logicalCanvasBytes = width * height * 4
        }
        guard data.count <= AvatarAnimationLimits.maximumFileBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              (2...AvatarAnimationLimits.maximumFrames).contains(CGImageSourceGetCount(source)),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              width <= AvatarAnimationLimits.maximumCanvasSide,
              height <= AvatarAnimationLimits.maximumCanvasSide,
              let image = SDAnimatedImage(data: data, scale: 1, options: [
                .decodeThumbnailPixelSize: NSValue(cgSize: CGSize(width: pixelSize, height: pixelSize)),
                .decodeUseLazyDecoding: false,
              ]), image.animatedImageFrameCount > 1,
              let first = image.cgImage, first.width <= pixelSize, first.height <= pixelSize else { return nil }
        return PreparedAvatarAnimation(image: image, dataBytes: data.count,
            warmCost: data.count + max(logicalCanvasBytes, width * height * 4) + first.bytesPerRow * first.height)
    }
}

@MainActor
final class TimelineAvatarAnimationPool {
    static let shared = TimelineAvatarAnimationPool()
    nonisolated struct Key: Hashable, Sendable {
        let url: URL
        let pixelSize: Int
    }
    private struct Consumer {
        let ready: (SDAnimatedImage) -> Void
        let invalidate: () -> Void
    }
    private final class Entry {
        // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
        nonisolated deinit {}

        let generation = UUID()
        var consumers: [UUID: Consumer] = [:]
        var prepared: PreparedAvatarAnimation?
        var loading: Task<Void, Never>?
        var expiry: Task<Void, Never>?
        var parkedAt: Date?
    }
    typealias Loader = (URL) async throws -> Data
    private let loader: Loader
    private let capacity: Int
    private let warmLimit: Int
    private let warmLifetime: TimeInterval
    private let warmBudget: Int
    private let dataBudget: Int
    private var entries: [Key: Entry] = [:]
    private var failures: [Key: Date] = [:]
    private var cooldownUntil = Date.distantPast
    private var lifecycleObservers: [NSObjectProtocol] = []
    let recovery = AvatarAnimationRecovery()
    private var recoveryTask: Task<Void, Never>?
    /// The account whose avatars the pool holds; switching accounts empties it once.
    private var accountKey: String?

    init(capacity: Int = AvatarAnimationLimits.maximumContexts,
         warmLimit: Int = AvatarAnimationLimits.warmCount,
         warmLifetime: TimeInterval = AvatarAnimationLimits.warmLifetime,
         warmBudget: Int = AvatarAnimationLimits.warmBudget,
         dataBudget: Int = AvatarAnimationLimits.dataBudget,
         observesLifecycle: Bool = true,
         loader: @escaping Loader = { try await AvatarAnimationDataStore.shared.data(for: $0) }) {
        self.capacity = min(capacity, AvatarAnimationLimits.maximumContexts)
        self.warmLimit = warmLimit
        self.warmLifetime = warmLifetime
        self.warmBudget = warmBudget
        self.dataBudget = dataBudget
        self.loader = loader
        if observesLifecycle {
            for name in [UIApplication.didReceiveMemoryWarningNotification, UIApplication.didEnterBackgroundNotification] {
                lifecycleObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                    queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.removeAll(cooldown: name == UIApplication.didReceiveMemoryWarningNotification ? 30 : 0)
                    }
                })
            }
            // Once for the whole pool, rather than from every avatar on screen.
            lifecycleObservers.append(NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if ProcessInfo.processInfo.isLowPowerModeEnabled { self?.removeAll() }
                }
            })
        }
    }

    var activeCount: Int { entries.values.reduce(0) { $0 + $1.consumers.count } }
    var warmCount: Int { entries.values.filter { $0.consumers.isEmpty }.count }
    var encodedBytes: Int { entries.values.reduce(0) { $0 + ($1.prepared?.dataBytes ?? 0) } }
    var reservedFrameBytes: Int { (activeCount + warmCount) * AvatarAnimationLimits.frameReservation }

    @discardableResult
    func acquire(_ key: Key, consumerID: UUID,
                 ready: @escaping (SDAnimatedImage) -> Void, invalidate: @escaping () -> Void) -> Bool {
        failures = failures.filter { $0.value > Date() }
        guard Date() >= cooldownUntil, failures[key] == nil else { return false }
        // A new visible consumer always has priority over a parked decoder.
        while activeCount + warmCount >= capacity, let oldest = oldestWarm(excluding: key) { evict(oldest) }
        let existing = entries[key]
        let replacesWarm = existing?.consumers.isEmpty == true ? 1 : 0
        guard activeCount + warmCount - replacesWarm < capacity else { return false }
        let entry = existing ?? Entry()
        entry.expiry?.cancel()
        entry.expiry = nil
        entry.parkedAt = nil
        entry.consumers[consumerID] = Consumer(ready: ready, invalidate: invalidate)
        entries[key] = entry
        if let prepared = entry.prepared { ready(prepared.image) }
        else if entry.loading == nil {
            let generation = entry.generation
            entry.loading = Task { [weak self, loader] in
                let prepared: PreparedAvatarAnimation?
                do {
                    let data = try await loader(key.url)
                    try Task.checkCancellation()
                    prepared = await AvatarAnimationDecoder.shared.prepare(data, pixelSize: key.pixelSize)
                } catch { prepared = nil }
                guard !Task.isCancelled else { return }
                self?.complete(key, generation: generation, prepared: prepared)
            }
        }
        return true
    }

    func release(_ key: Key, consumerID: UUID) {
        guard let entry = entries[key], entry.consumers.removeValue(forKey: consumerID) != nil,
              entry.consumers.isEmpty else { return }
        guard let prepared = entry.prepared, prepared.warmCost <= warmBudget, warmLimit > 0 else {
            evict(key)
            return
        }
        entry.parkedAt = Date()
        entry.expiry = Task { [weak self, weak entry] in
            try? await Task.sleep(for: .seconds(self?.warmLifetime ?? 0))
            guard !Task.isCancelled, let self, let entry, self.entries[key] === entry,
                  entry.consumers.isEmpty else { return }
            self.evict(key)
        }
        trimWarm()
    }

    /// Every avatar on screen reports the account; only a real switch empties the pool.
    func noteAccount(_ key: String?) {
        guard key != accountKey else { return }
        let hadAccount = accountKey != nil
        accountKey = key
        if hadAccount { removeAll() }
    }

    func removeAll(cooldown: TimeInterval = 0) {
        // Many avatars can ask at once (a setting turned off); after the first there is
        // nothing to drop, and restarting every avatar's settle timer would be wasted work.
        guard cooldown > 0 || !entries.isEmpty else { return }
        recoveryTask?.cancel()
        cooldownUntil = Date().addingTimeInterval(cooldown)
        let removed = entries
        entries.removeAll()
        for entry in removed.values {
            entry.loading?.cancel()
            entry.expiry?.cancel()
            entry.consumers.values.forEach { $0.invalidate() }
        }
        if cooldown > 0 {
            recoveryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(cooldown))
                guard !Task.isCancelled, let self else { return }
                self.recovery.revision &+= 1
            }
        } else { recovery.revision &+= 1 }
    }

    private func complete(_ key: Key, generation: UUID, prepared: PreparedAvatarAnimation?) {
        guard let entry = entries[key], entry.generation == generation else { return }
        entry.loading = nil
        guard let prepared else {
            if failures.count >= 128, let oldest = failures.min(by: { $0.value < $1.value })?.key {
                failures[oldest] = nil
            }
            failures[key] = Date().addingTimeInterval(60)
            evict(key)
            return
        }
        while encodedBytes + prepared.dataBytes > dataBudget, let oldest = oldestWarm() { evict(oldest) }
        guard encodedBytes + prepared.dataBytes <= dataBudget else { evict(key); return }
        entry.prepared = prepared
        // Callbacks may release a consumer, so iterate a snapshot.
        Array(entry.consumers.values).forEach { $0.ready(prepared.image) }
    }

    private func oldestWarm(excluding key: Key? = nil) -> Key? {
        entries.filter { $0.key != key && $0.value.consumers.isEmpty }
            .min { ($0.value.parkedAt ?? .distantPast) < ($1.value.parkedAt ?? .distantPast) }?.key
    }

    private func trimWarm() {
        while warmCount > warmLimit || entries.values.filter({ $0.consumers.isEmpty })
            .reduce(0, { $0 + ($1.prepared?.warmCost ?? 0) }) > warmBudget {
            guard let oldest = oldestWarm() else { break }
            evict(oldest)
        }
    }

    private func evict(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        entry.loading?.cancel()
        entry.expiry?.cancel()
        entry.consumers.values.forEach { $0.invalidate() }
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        recoveryTask?.cancel()
    }
}

@MainActor @Observable final class AvatarAnimationRecovery {
    // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
    nonisolated deinit {}

    var revision: UInt = 0
}
