import Combine
import Foundation
import SDWebImage

@MainActor
final class StorageManagementStore: ObservableObject {
    static let shared = StorageManagementStore()
    struct Usage {
        let images: Int64
        let timelines: Int64
        let responses: Int64
        var total: Int64 { images + timelines + responses }
    }
    @Published private(set) var usage: Usage?
    @Published private(set) var isClearing = false
    @Published private(set) var failed = false

    static func configureImageCache() {
        SDImageCache.shared.config.maxDiskSize = 256 * 1_024 * 1_024
        SDImageCache.shared.config.maxDiskAge = 7 * 86_400
        SDImageCache.shared.deleteOldFiles { }
    }

    func refresh() async {
        let images = await ImageCache.shared.diskSize()
        let media: UInt = await withCheckedContinuation { continuation in
            SDImageCache.shared.calculateSize { _, size in continuation.resume(returning: size) }
        }
        let timelines = await CacheManager.shared.timelineCache.contentDiskSize()
        usage = Usage(images: images + Int64(media), timelines: timelines, responses: Int64(URLCache.shared.currentDiskUsage))
    }

    func clear() async {
        guard !isClearing else { return }
        isClearing = true
        failed = false
        NotificationCenter.default.post(name: .timelineContentWillClear, object: CacheManager.shared.timelineCache)
        CacheManager.shared.threadCache.invalidateAll()
        CacheManager.shared.accountCache.clear()
        SDWebImageManager.shared.cancelAll()
        SDImageCache.shared.clearMemory()
        await withCheckedContinuation { continuation in
            SDImageCache.shared.clearDisk { continuation.resume() }
        }
        do { try await ImageCache.shared.clearAllAndWait() } catch { failed = true }
        do { try await CacheManager.shared.timelineCache.clearContentCache() } catch { failed = true }
        URLCache.shared.removeAllCachedResponses()
        await refresh()
        isClearing = false
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
