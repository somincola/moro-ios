//
//  AccountCache.swift
//  moro
//
//  In-memory cache for Account objects encountered in timeline/threads.
//

import Foundation
import Combine

/// In-memory cache for Account objects
@MainActor
final class AccountCache: ObservableObject {
    /// Cached accounts by ID
    private var cache: [String: Account] = [:]

    /// Maximum number of accounts to cache
    private let maxCacheSize: Int

    /// Monotonic access stamp per ID — gives O(1) LRU touch instead of the O(n)
    /// firstIndex/remove an ordered array required on every get/set.
    private var accessTick: [String: UInt64] = [:]
    private var tick: UInt64 = 0

    init(maxCacheSize: Int = 500) {
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Cache Operations

    /// Get a cached account by ID
    func get(id: String) -> Account? {
        guard let account = cache[id] else { return nil }
        tick &+= 1
        accessTick[id] = tick
        return account
    }

    /// Store an account in the cache
    func set(_ account: Account) {
        // Evict the least-recently-used entries before inserting a new key.
        if cache[account.id] == nil {
            while cache.count >= maxCacheSize,
                  let oldest = accessTick.min(by: { $0.value < $1.value })?.key {
                cache.removeValue(forKey: oldest)
                accessTick.removeValue(forKey: oldest)
            }
        }

        tick &+= 1
        cache[account.id] = account
        accessTick[account.id] = tick
    }
    
    /// Cache all accounts from a list of statuses
    func cacheFromStatuses(_ statuses: [Status]) {
        for status in statuses {
            set(status.account)
            
            // Also cache the reblogged/quoted status's account if present
            if let reblog = status.reblog?.value {
                set(reblog.account)
            }
            if let quote = status.quote?.displayableStatus {
                set(quote.account)
            }
        }
    }
    
    /// Cache all accounts from thread items
    func cacheFromThread(_ threadItems: [ThreadItem]) {
        for item in threadItems {
            set(item.status.account)
        }
    }
    
    /// Get avatar URL for an account ID (useful for reply headers)
    func getAvatarURL(for accountID: String) -> URL? {
        return cache[accountID]?.avatarURL
    }
    
    /// Get display name for an account ID
    func getDisplayName(for accountID: String) -> String? {
        return cache[accountID]?.displayName
    }
    
    /// Clear all cached accounts
    func clear() {
        cache.removeAll()
        accessTick.removeAll()
        tick = 0
    }
    
    /// Number of cached accounts
    var count: Int {
        return cache.count
    }
}
