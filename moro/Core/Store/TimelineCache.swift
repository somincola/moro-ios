//
//  TimelineCache.swift
//  moro
//
//  Actor-based timeline cache with disk persistence for offline support.
//

import Foundation

/// Timeline filter identifier
enum TimelineFilter: String, Codable, Hashable, Sendable {
    case home = "Home"
    case local = "Local"
    case federated = "Federated"
    case hashtag = "Hashtag"

    nonisolated var cacheKey: String { rawValue }
}

/// Actor for thread-safe timeline caching with persistence
actor TimelineCache {

    // MARK: - Types

    /// Cached timeline item wrapper
    private struct CachedItem: Codable {
        let status: Status
        let cachedAt: Date
    }

    /// Cache metadata
    private struct CacheMetadata: Codable {
        var lastUpdated: Date
        var itemCount: Int
        var lastSeenStatusIds: [String]
    }

    // MARK: - Configuration

    /// Maximum number of statuses to cache per timeline
    private let maxCachedStatuses: Int

    /// Cache expiration time (24 hours)
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60

    /// Base directory for cache files
    private let cacheDirectory: URL

    // MARK: - In-Memory State

    /// In-memory cache for quick access
    private var memoryCache: [String: [CachedItem]] = [:]

    /// Metadata for each cache
    private var metadata: [String: CacheMetadata] = [:]

    /// Dirty flags for pending writes
    private var dirtyKeys: Set<String> = []

    // MARK: - Initialization

    init(maxCachedStatuses: Int = 800) {
        self.maxCachedStatuses = maxCachedStatuses

        // Use app's cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDir.appendingPathComponent("TimelineCache", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Cache statuses for a timeline
    func set(statuses: [Status], for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        let now = Date()

        // Limit to max cached statuses
        let limitedStatuses = Array(statuses.prefix(maxCachedStatuses))
        let items = limitedStatuses.map { CachedItem(status: $0, cachedAt: now) }

        memoryCache[key] = items
        metadata[key] = CacheMetadata(
            lastUpdated: now,
            itemCount: items.count,
            lastSeenStatusIds: []
        )
        dirtyKeys.insert(key)

        // Persist to disk asynchronously
        Task.detached(priority: .background) { [weak self] in
            await self?.persistCache(key: key)
        }
    }

    /// Get cached statuses for a timeline
    func getStatuses(for client: String, filter: TimelineFilter) async -> [Status]? {
        let key = cacheKey(client: client, filter: filter)

        // Try memory cache first
        if let items = memoryCache[key] {
            // Check expiration
            if let firstItem = items.first,
                Date().timeIntervalSince(firstItem.cachedAt) < cacheExpirationInterval
            {
                return items.map { $0.status }
            }
        }

        // Try loading from disk
        if let items = await loadFromDisk(key: key) {
            memoryCache[key] = items
            return items.map { $0.status }
        }

        return nil
    }

    /// Prepend new statuses to cache (for refresh)
    func prepend(statuses: [Status], for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        let now = Date()

        let newItems = statuses.map { CachedItem(status: $0, cachedAt: now) }
        var items = memoryCache[key] ?? []

        // Remove duplicates by ID
        let newIds = Set(statuses.map { $0.id })
        items.removeAll { newIds.contains($0.status.id) }

        // Prepend and limit
        items = newItems + items
        items = Array(items.prefix(maxCachedStatuses))

        memoryCache[key] = items
        metadata[key]?.lastUpdated = now
        metadata[key]?.itemCount = items.count
        dirtyKeys.insert(key)

        Task.detached(priority: .background) { [weak self] in
            await self?.persistCache(key: key)
        }
    }

    /// Append statuses to cache (for pagination)
    func append(statuses: [Status], for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)
        let now = Date()

        let newItems = statuses.map { CachedItem(status: $0, cachedAt: now) }
        var items = memoryCache[key] ?? []

        // Remove duplicates by ID
        let existingIds = Set(items.map { $0.status.id })
        let uniqueNewItems = newItems.filter { !existingIds.contains($0.status.id) }

        items.append(contentsOf: uniqueNewItems)
        items = Array(items.prefix(maxCachedStatuses))

        memoryCache[key] = items
        dirtyKeys.insert(key)

        Task.detached(priority: .background) { [weak self] in
            await self?.persistCache(key: key)
        }
    }

    /// Update a single status in cache
    func updateStatus(_ status: Status, for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)

        guard var items = memoryCache[key] else { return }

        if let index = items.firstIndex(where: { $0.status.id == status.id }) {
            items[index] = CachedItem(status: status, cachedAt: Date())
            memoryCache[key] = items
            dirtyKeys.insert(key)

            Task.detached(priority: .background) { [weak self] in
                await self?.persistCache(key: key)
            }
        }
    }

    /// Remove a status from cache
    func removeStatus(id: String, for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)

        guard var items = memoryCache[key] else { return }

        items.removeAll { $0.status.id == id }
        memoryCache[key] = items
        metadata[key]?.itemCount = items.count
        dirtyKeys.insert(key)

        Task.detached(priority: .background) { [weak self] in
            await self?.persistCache(key: key)
        }
    }

    /// Clear cache for a specific timeline
    func clearCache(for client: String, filter: TimelineFilter) {
        let key = cacheKey(client: client, filter: filter)

        memoryCache[key] = nil
        metadata[key] = nil
        dirtyKeys.remove(key)

        // Remove from disk
        let fileURL = cacheFileURL(for: key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Clear all caches for a client
    func clearCache(for client: String) {
        let prefix = "\(client)-"

        memoryCache = memoryCache.filter { !$0.key.hasPrefix(prefix) }
        metadata = metadata.filter { !$0.key.hasPrefix(prefix) }
        dirtyKeys = dirtyKeys.filter { !$0.hasPrefix(prefix) }

        // Remove client directory
        let clientDir = cacheDirectory.appendingPathComponent(client)
        try? FileManager.default.removeItem(at: clientDir)
    }

    /// Clear all caches
    func clearAllCaches() {
        memoryCache.removeAll()
        metadata.removeAll()
        dirtyKeys.removeAll()

        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Marker Support (Last Seen Status)

    /// Save last seen status IDs for a timeline
    func setLastSeenStatuses(
        _ statusIds: [String], for client: String, filter: TimelineFilter
    ) {
        let key = cacheKey(client: client, filter: filter)

        if metadata[key] != nil {
            metadata[key]?.lastSeenStatusIds = statusIds
        } else {
            metadata[key] = CacheMetadata(
                lastUpdated: Date(),
                itemCount: 0,
                lastSeenStatusIds: statusIds
            )
        }

        // Persist metadata
        Task.detached(priority: .background) { [weak self] in
            await self?.persistMetadata(key: key)
        }
    }

    /// Get last seen status IDs for a timeline
    func getLastSeenStatuses(for client: String, filter: TimelineFilter) -> [String]? {
        let key = cacheKey(client: client, filter: filter)
        return metadata[key]?.lastSeenStatusIds
    }

    // MARK: - Statistics

    /// Get cached post count for a client
    func cachedPostsCount(for client: String) -> Int {
        let prefix = "\(client)-"
        return
            memoryCache
            .filter { $0.key.hasPrefix(prefix) }
            .reduce(0) { $0 + $1.value.count }
    }

    /// Get cache statistics
    func stats() -> (timelines: Int, totalStatuses: Int) {
        let timelines = memoryCache.count
        let statuses = memoryCache.values.reduce(0) { $0 + $1.count }
        return (timelines, statuses)
    }

    // MARK: - Private Helpers

    private func cacheKey(client: String, filter: TimelineFilter) -> String {
        "\(client)-\(filter.cacheKey)"
    }

    private func cacheFileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).cache")
    }

    private func metadataFileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).meta")
    }

    private func persistCache(key: String) {
        guard dirtyKeys.contains(key),
            let items = memoryCache[key]
        else { return }

        dirtyKeys.remove(key)

        let fileURL = cacheFileURL(for: key)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL)
        } catch {
            // Ignore persistence errors to avoid affecting timeline rendering.
        }
    }

    private func persistMetadata(key: String) {
        guard let meta = metadata[key] else { return }

        let fileURL = metadataFileURL(for: key)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(meta)
            try data.write(to: fileURL)
        } catch {
            // Ignore metadata persistence errors to avoid affecting timeline rendering.
        }
    }

    private func loadFromDisk(key: String) async -> [CachedItem]? {
        let fileURL = cacheFileURL(for: key)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([CachedItem].self, from: data)

            // Check expiration
            if let firstItem = items.first,
                Date().timeIntervalSince(firstItem.cachedAt) >= cacheExpirationInterval
            {
                // Cache expired, remove it
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            return items
        } catch {
            // Fall back to network if disk cache load fails.
            return nil
        }
    }

    private func loadMetadata(key: String) -> CacheMetadata? {
        let fileURL = metadataFileURL(for: key)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(CacheMetadata.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Hashtag Timeline Support

extension TimelineCache {
    /// Cache key for hashtag timeline
    private func hashtagCacheKey(client: String, hashtag: String) -> String {
        "\(client)-Hashtag-\(hashtag.lowercased())"
    }

    /// Cache statuses for a hashtag timeline
    func set(statuses: [Status], for client: String, hashtag: String) {
        let key = hashtagCacheKey(client: client, hashtag: hashtag)
        let now = Date()

        let limitedStatuses = Array(statuses.prefix(maxCachedStatuses))
        let items = limitedStatuses.map { CachedItem(status: $0, cachedAt: now) }

        memoryCache[key] = items
        metadata[key] = CacheMetadata(
            lastUpdated: now,
            itemCount: items.count,
            lastSeenStatusIds: []
        )

        Task.detached(priority: .background) { [weak self] in
            await self?.persistCache(key: key)
        }
    }

    /// Get cached statuses for a hashtag timeline
    func getStatuses(for client: String, hashtag: String) async -> [Status]? {
        let key = hashtagCacheKey(client: client, hashtag: hashtag)

        if let items = memoryCache[key] {
            if let firstItem = items.first,
                Date().timeIntervalSince(firstItem.cachedAt) < cacheExpirationInterval
            {
                return items.map { $0.status }
            }
        }

        if let items = await loadFromDisk(key: key) {
            memoryCache[key] = items
            return items.map { $0.status }
        }

        return nil
    }
}
