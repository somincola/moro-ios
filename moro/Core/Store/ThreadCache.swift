//
//  ThreadCache.swift
//  moro
//
//  In-memory cache for loaded thread conversations.
//

import Foundation
import Combine

/// In-memory cache for thread conversations
@MainActor
final class ThreadCache: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private static let maximumLifetime: TimeInterval = 300

    /// Cached thread models by focused status ID
    private var cache: [String: CachedThread] = [:]
    
    /// Maximum number of threads to cache
    private let maxCacheSize: Int

    /// Monotonic access stamp per ID — gives O(1) LRU touch instead of the O(n)
    /// firstIndex/remove an ordered array required on every get/set.
    private var accessTick: [String: UInt64] = [:]
    private var tick: UInt64 = 0

    init(maxCacheSize: Int = 50) {
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Cache Operations

    /// Get a cached thread for a status ID
    func get(statusID: String) -> ThreadedConversationModel? {
        guard let cached = cache[statusID] else { return nil }

        // Check if cache is still valid (within 5 minutes)
        if Date().timeIntervalSince(cached.timestamp) > Self.maximumLifetime {
            invalidate(statusID: statusID)
            return nil
        }

        tick &+= 1
        accessTick[statusID] = tick
        return cached.model
    }

    /// Store a thread in the cache
    func set(
        _ thread: ThreadedConversationModel,
        for statusID: String,
        timestamp: Date = Date()
    ) {
        // Evict the least-recently-used entries before inserting a new key.
        if cache[statusID] == nil {
            while cache.count >= maxCacheSize,
                  let oldest = accessTick.min(by: { $0.value < $1.value })?.key {
                invalidate(statusID: oldest)
            }
        }

        tick &+= 1
        cache[statusID] = CachedThread(model: thread, timestamp: timestamp)
        accessTick[statusID] = tick
    }

    /// Whether a cached thread is recent enough to be used without a network
    /// revalidation. This is intentionally separate from the five-minute
    /// lifetime: an older entry can still provide an immediate first frame,
    /// while volatile interaction counts are refreshed in the background.
    func isFresh(statusID: String, maximumAge: TimeInterval) -> Bool {
        guard let cached = cache[statusID] else { return false }
        let age = max(0, Date().timeIntervalSince(cached.timestamp))
        return age <= min(maximumAge, Self.maximumLifetime)
    }

    /// Invalidate a specific thread cache
    func invalidate(statusID: String) {
        cache.removeValue(forKey: statusID)
        accessTick.removeValue(forKey: statusID)
    }

    /// Invalidate all cached threads
    func invalidateAll() {
        cache.removeAll()
        accessTick.removeAll()
        tick = 0
    }
    
    /// Check if a thread is cached and still valid
    func isCached(statusID: String) -> Bool {
        guard let cached = cache[statusID] else { return false }
        return Date().timeIntervalSince(cached.timestamp) <= Self.maximumLifetime
    }
}

// MARK: - Supporting Types

private struct CachedThread {
    let model: ThreadedConversationModel
    let timestamp: Date
}
