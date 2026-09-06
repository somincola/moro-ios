import CryptoKit
import Foundation

/// Source identity is independent of display titles. List IDs never become file paths.
enum TimelineFilter: Codable, Hashable, Sendable {
    case home, local, federated, hashtag
    case list(id: String)

    nonisolated var cacheKey: String {
        switch self {
        case .home: "Home"
        case .local: "Local"
        case .federated: "Federated"
        case .hashtag: "Hashtag"
        case .list(let id):
            "List-" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
}

/// Bounded account/source caches; disk writes and mutations share one actor.
actor TimelineCache {
    private struct CachedItem: Codable {
        let status: Status
        let cachedAt: Date
    }
    private struct CacheMetadata: Codable {
        var lastUpdated: Date
        var itemCount: Int
        var lastSeenStatusIds: [String]
    }

    private let maxCachedStatuses: Int
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60
    private let cacheDirectory: URL
    private var memoryCache: [String: [CachedItem]] = [:]
    private var metadata: [String: CacheMetadata] = [:]
    private var dirtyKeys: Set<String> = []
    private var dirtyMetadataKeys: Set<String> = []
    private var persistenceTask: Task<Void, Never>?

    init(maxCachedStatuses: Int = 800, directory: URL? = nil) {
        self.maxCachedStatuses = max(1, maxCachedStatuses)
        cacheDirectory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimelineCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func set(statuses: [Status], for client: String, filter: TimelineFilter) {
        assign(statuses, key: cacheKey(client: client, filter: filter))
    }

    func getStatuses(for client: String, filter: TimelineFilter) async -> [Status]? {
        items(for: cacheKey(client: client, filter: filter))?.map(\.status)
    }

    func prepend(statuses: [Status], for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        assign(statuses + (items(for: key)?.map(\.status) ?? []), key: key)
    }

    func append(statuses: [Status], for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        assign((items(for: key)?.map(\.status) ?? []) + statuses, key: key)
    }

    func updateStatus(_ status: Status, for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        guard let existing = items(for: key), existing.contains(where: { $0.status.id == status.id }) else { return }
        assign(existing.map { $0.status.id == status.id ? status : $0.status }, key: key)
    }

    func removeStatus(id: String, for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        guard let existing = items(for: key) else { return }
        assign(existing.map(\.status).filter { $0.id != id }, key: key)
    }

    func clearCache(for client: String, filter: TimelineFilter) {
        clear(key: cacheKey(client: client, filter: filter))
    }

    func clearCache(for client: String) {
        let prefix = "\(client)-"
        let keys = Set(memoryCache.keys).union(metadata.keys).union(dirtyKeys).union(dirtyMetadataKeys)
        for key in keys where key.hasPrefix(prefix) { clear(key: key) }
        // Files are stored flat, including caches that have not been read this session.
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func clearAllCaches() {
        memoryCache.removeAll()
        metadata.removeAll()
        dirtyKeys.removeAll()
        dirtyMetadataKeys.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Memory pressure must not discard the offline copy on disk.
    func releaseMemory() {
        flushPendingWrites()
        memoryCache = memoryCache.filter { dirtyKeys.contains($0.key) }
        metadata = metadata.filter { dirtyMetadataKeys.contains($0.key) }
    }

    func setLastSeenStatuses(_ statusIds: [String], for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        var meta = metadataForKey(key) ?? CacheMetadata(lastUpdated: Date(), itemCount: 0, lastSeenStatusIds: [])
        meta.lastSeenStatusIds = statusIds
        metadata[key] = meta
        dirtyMetadataKeys.insert(key)
        schedulePersistence()
    }

    func getLastSeenStatuses(for client: String, filter: TimelineFilter) -> [String]? {
        metadataForKey(cacheKey(client: client, filter: filter))?.lastSeenStatusIds
    }

    func cachedPostsCount(for client: String) -> Int {
        memoryCache.filter { $0.key.hasPrefix("\(client)-") }.reduce(0) { $0 + $1.value.count }
    }

    func stats() -> (timelines: Int, totalStatuses: Int) {
        (memoryCache.count, memoryCache.values.reduce(0) { $0 + $1.count })
    }

    func set(statuses: [Status], for client: String, hashtag: String) {
        assign(statuses, key: "\(client)-Hashtag-\(hashtag.lowercased())")
    }

    func getStatuses(for client: String, hashtag: String) async -> [Status]? {
        items(for: "\(client)-Hashtag-\(hashtag.lowercased())")?.map(\.status)
    }

    /// Also provides an explicit durability boundary for backgrounding and tests.
    func flushPendingWrites() {
        for key in dirtyKeys {
            guard let items = memoryCache[key] else { continue }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(items).write(to: fileURL(key, extension: "cache"), options: .atomic)
                dirtyKeys.remove(key)
            } catch { /* Retain dirty state so the next flush can retry. */ }
        }
        for key in dirtyMetadataKeys {
            guard let meta = metadata[key] else { continue }
            do {
                try JSONEncoder().encode(meta).write(to: fileURL(key, extension: "meta"), options: .atomic)
                dirtyMetadataKeys.remove(key)
            } catch { /* Metadata has the same retry boundary as cached bodies. */ }
        }
    }

    private func assign(_ statuses: [Status], key: String) {
        var seen = Set<String>()
        let unique = statuses.filter { seen.insert($0.id).inserted }.prefix(maxCachedStatuses)
        let now = Date()
        let lastSeen = metadataForKey(key)?.lastSeenStatusIds ?? []
        memoryCache[key] = unique.map { CachedItem(status: $0, cachedAt: now) }
        metadata[key] = CacheMetadata(lastUpdated: now, itemCount: unique.count, lastSeenStatusIds: lastSeen)
        dirtyKeys.insert(key)
        dirtyMetadataKeys.insert(key)
        schedulePersistence()
    }

    private func items(for key: String) -> [CachedItem]? {
        let cached: [CachedItem]?
        if let memory = memoryCache[key] { cached = memory }
        else {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cached = (try? Data(contentsOf: fileURL(key, extension: "cache")))
                .flatMap { try? decoder.decode([CachedItem].self, from: $0) }
        }
        guard let cached else { return nil }
        if let first = cached.first, Date().timeIntervalSince(first.cachedAt) >= cacheExpirationInterval {
            clear(key: key)
            return nil
        }
        memoryCache[key] = cached
        return cached
    }

    private func metadataForKey(_ key: String) -> CacheMetadata? {
        if let meta = metadata[key] { return meta }
        guard let data = try? Data(contentsOf: fileURL(key, extension: "meta")),
              let meta = try? JSONDecoder().decode(CacheMetadata.self, from: data) else { return nil }
        metadata[key] = meta
        return meta
    }

    private func schedulePersistence() {
        guard persistenceTask == nil else { return }
        persistenceTask = Task.detached(priority: .background) { [weak self] in
            await self?.persistScheduledWrites()
        }
    }

    private func persistScheduledWrites() {
        flushPendingWrites()
        persistenceTask = nil
    }

    private func clear(key: String) {
        memoryCache[key] = nil
        metadata[key] = nil
        dirtyKeys.remove(key)
        dirtyMetadataKeys.remove(key)
        try? FileManager.default.removeItem(at: fileURL(key, extension: "cache"))
        try? FileManager.default.removeItem(at: fileURL(key, extension: "meta"))
    }

    private func cacheKey(client: String, filter: TimelineFilter) -> String { "\(client)-\(filter.cacheKey)" }
    private func fileURL(_ key: String, extension ext: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).\(ext)")
    }
}
