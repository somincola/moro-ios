//
//  CacheManager.swift
//  moro
//
//  Centralized cache management for the app.
//

import Combine
import Foundation
import SwiftUI

/// Centralized manager for all app caches
@MainActor
final class CacheManager: ObservableObject {
    /// Shared singleton instance
    static let shared = CacheManager()

    /// Cache for thread conversations
    let threadCache: ThreadCache

    /// Cache for account information
    let accountCache: AccountCache

    /// Cache for timelines with disk persistence
    let timelineCache: TimelineCache

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private init() {
        self.threadCache = ThreadCache(maxCacheSize: 50)
        self.accountCache = AccountCache(maxCacheSize: 500)
        self.timelineCache = TimelineCache(maxCachedStatuses: 800)
        startMemoryPressureMonitoring()
    }

    // MARK: - Cache Operations

    /// Clear all caches (e.g., on logout)
    func clearAll() {
        threadCache.invalidateAll()
        accountCache.clear()
        TranslationLanguagesStore.shared.reset()
        Task {
            await timelineCache.clearAllCaches()
        }
    }

    /// Clear caches for a specific client/account
    func clearForClient(_ clientId: String) {
        Task {
            await timelineCache.clearCache(for: clientId)
        }
    }

    // MARK: - Memory Pressure

    /// Free in-memory caches when the OS reports memory pressure. `threadCache` and
    /// `accountCache` are plain-dictionary LRUs, so — unlike `NSCache` — they never
    /// auto-evict; without this they stay resident and can get the app jetsam-killed
    /// during a long, media-heavy scroll session. On `.warning` we drop the soft caches
    /// (thread + account) and the 50 MB image memory cache; on `.critical` we also drop
    /// the in-memory timeline while retaining its offline copy on disk.
    func handleMemoryPressure(critical: Bool) {
        threadCache.invalidateAll()
        accountCache.clear()
        ImageCache.shared.clearMemoryCache()
        if critical {
            Task { await timelineCache.releaseMemory() }
        }
    }

    /// Observe OS memory-pressure events and flush caches accordingly. Lives for the
    /// app's lifetime (CacheManager is a singleton), so no teardown is needed.
    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.memoryPressureSource else { return }
                self.handleMemoryPressure(critical: source.data.contains(.critical))
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    /// Get memory usage statistics
    func getCacheStats() async -> CacheStatistics {
        let (timelineCount, statusCount) = await timelineCache.stats()
        return CacheStatistics(
            threadCacheCount: 0,  // ThreadCache doesn't expose count
            accountCacheCount: accountCache.count,
            timelineCacheCount: timelineCount,
            cachedStatusCount: statusCount
        )
    }

    /// Get cached posts count for a specific client
    func cachedPostsCount(for clientId: String) async -> Int {
        await timelineCache.cachedPostsCount(for: clientId)
    }
}

/// Statistics about cache usage
struct CacheStatistics {
    let threadCacheCount: Int
    let accountCacheCount: Int
    let timelineCacheCount: Int
    let cachedStatusCount: Int

    var totalItems: Int {
        threadCacheCount + accountCacheCount + cachedStatusCount
    }
}

// MARK: - Environment Key

private struct CacheManagerKey: EnvironmentKey {
    static let defaultValue: CacheManager = .shared
}

extension EnvironmentValues {
    var cacheManager: CacheManager {
        get { self[CacheManagerKey.self] }
        set { self[CacheManagerKey.self] = newValue }
    }
}

extension View {
    /// Inject a cache manager into the environment
    func cacheManager(_ manager: CacheManager) -> some View {
        environment(\.cacheManager, manager)
    }
}
