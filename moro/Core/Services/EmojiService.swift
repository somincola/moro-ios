//
//  EmojiService.swift
//  moro
//
//  Service for managing custom emojis from Mastodon instances.
//  Singleton pattern with per-instance caching.
//

import Foundation
import Combine
import SwiftUI

nonisolated struct EmojiCatalogCacheRecord: Codable {
    let fetchedAt: Date
    let emojis: [CustomEmoji]
}

nonisolated enum EmojiCatalogDiskCache {
    static let freshnessInterval: TimeInterval = 24 * 60 * 60

    static func load(
        domain: String,
        cacheDirectory: URL? = nil,
        legacyUserDefaults: UserDefaults = .standard
    ) -> EmojiCatalogCacheRecord? {
        let fileURL = cacheFileURL(domain: domain, cacheDirectory: cacheDirectory)
        if let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
           let record = try? JSONDecoder().decode(EmojiCatalogCacheRecord.self, from: data) {
            return record
        }

        let legacyKey = "emoji_cache_\(domain)"
        guard let legacyData = legacyUserDefaults.data(forKey: legacyKey),
              let emojis = try? JSONDecoder().decode([CustomEmoji].self, from: legacyData) else {
            return nil
        }

        // The legacy payload has no age metadata. Show it immediately, but mark it stale so
        // the first consumer refreshes it once from the server.
        let migratedRecord = EmojiCatalogCacheRecord(fetchedAt: .distantPast, emojis: emojis)
        if save(migratedRecord, domain: domain, cacheDirectory: cacheDirectory) {
            legacyUserDefaults.removeObject(forKey: legacyKey)
        }
        return migratedRecord
    }

    @discardableResult
    static func save(
        _ record: EmojiCatalogCacheRecord,
        domain: String,
        cacheDirectory: URL? = nil
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        let fileURL = cacheFileURL(domain: domain, cacheDirectory: cacheDirectory)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func isFresh(_ record: EmojiCatalogCacheRecord, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(record.fetchedAt)
        return age >= 0 && age < freshnessInterval
    }

    private static func cacheFileURL(domain: String, cacheDirectory: URL?) -> URL {
        let baseDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = baseDirectory.appendingPathComponent("EmojiCatalogs", isDirectory: true)
        let normalizedDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let fileName = Data(normalizedDomain.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent("\(fileName).json")
    }
}

@MainActor
final class EmojiService: ObservableObject {
    /// Shared singleton instance
    static let shared = EmojiService()
    
    /// Dictionary of custom emoji view models by domain
    private(set) var customEmojiViewModelDict: [String: CustomEmojiViewModel] = [:]
    
    /// API client for fetching emojis
    private var apiClient: MastodonAPI?
    
    private init() {}
    
    /// Set API client for emoji fetching
    func setAPIClient(_ apiClient: MastodonAPI) {
        self.apiClient = apiClient
        // Update all existing view models
        for viewModel in customEmojiViewModelDict.values {
            viewModel.setAPIClient(apiClient)
        }
    }
    
    /// Get or create a custom emoji view model for a domain
    func dequeueCustomEmojiViewModel(for domain: String, apiClient: MastodonAPI? = nil) -> CustomEmojiViewModel? {
        let normalizedDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedDomain.isEmpty else { return nil }

        let client = apiClient ?? self.apiClient
        if let viewModel = customEmojiViewModelDict[normalizedDomain] {
            if let client {
                viewModel.setAPIClient(client)
            }
            return viewModel
        }

        let viewModel = CustomEmojiViewModel(
            domain: normalizedDomain,
            service: self,
            apiClient: client
        )
        customEmojiViewModelDict[normalizedDomain] = viewModel

        // A single bootstrap task owns disk restore, freshness checks and any network refresh.
        viewModel.load()
        return viewModel
    }
}

/// View model for custom emojis from a specific domain
@MainActor
final class CustomEmojiViewModel: ObservableObject {
    enum LoadState {
        case initial
        case loading
        case finish
        case fail
    }
    
    let domain: String
    private weak var service: EmojiService?
    private var apiClient: MastodonAPI?
    
    @Published var loadState: LoadState = .initial
    @Published var emojis: [CustomEmoji]? = nil
    @Published private(set) var orderedGroupNames: [String] = []
    @Published var emojiDict: [String: [CustomEmoji]]? = nil
    @Published var emojiMapping: [String: String] = [:]
    @Published var emojiTrie: EmojiTrie? = nil
    
    /// Bounded exponential-backoff retry state. Re-entering load cancels any
    /// pending wakeup instead of stacking retries.
    private var pendingRetryTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var automaticRetryCount = 0
    private let maximumAutomaticRetryCount = 2

    // Emoji groups by category
    @Published var emojiGroups: [EmojiGroup] = []
    @Published var selectedGroupIndex: Int = 0

    init(domain: String, service: EmojiService, apiClient: MastodonAPI? = nil) {
        self.domain = domain
        self.service = service
        self.apiClient = apiClient
    }

    deinit {
        pendingRetryTask?.cancel()
        loadTask?.cancel()
    }

    /// Schedule at most two automatic retries (2s, then 4s). After that the
    /// picker exposes its explicit retry action instead of polling indefinitely.
    private func scheduleRetry() {
        guard automaticRetryCount < maximumAutomaticRetryCount else { return }
        let delaySeconds = UInt64(2 << automaticRetryCount)
        automaticRetryCount += 1
        pendingRetryTask?.cancel()
        pendingRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.startLoad(resetAutomaticRetryCount: false)
        }
    }
    
    /// Set API client for loading emojis
    func setAPIClient(_ apiClient: MastodonAPI) {
        self.apiClient = apiClient
        if loadState == .initial || loadState == .fail {
            load()
        }
    }
    
    /// Save large emoji catalogs as cache files instead of inflating UserDefaults.
    private func saveToCache(_ emojis: [CustomEmoji]) {
        let domain = domain
        let record = EmojiCatalogCacheRecord(fetchedAt: Date(), emojis: emojis)
        Task.detached(priority: .utility) {
            EmojiCatalogDiskCache.save(record, domain: domain)
        }
    }
    
    func load(forceRefresh: Bool = false) {
        startLoad(
            resetAutomaticRetryCount: true,
            forceRefresh: forceRefresh
        )
    }

    private func startLoad(
        resetAutomaticRetryCount: Bool,
        forceRefresh: Bool = false
    ) {
        if resetAutomaticRetryCount {
            automaticRetryCount = 0
        }

        // Re-entering load() supersedes any in-flight retry wakeup.
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        guard loadTask == nil else { return }

        // If already loaded from cache, we can still refresh in background
        let shouldShowLoading = loadState == .initial || loadState == .fail
        if shouldShowLoading {
            loadState = .loading
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.loadTask = nil }

            if self.emojis == nil {
                let domain = self.domain
                let cachedRecord = await Task.detached(priority: .userInitiated) {
                    EmojiCatalogDiskCache.load(domain: domain)
                }.value
                if let cachedRecord {
                    self.emojis = cachedRecord.emojis
                    self.buildDataStructures(from: cachedRecord.emojis)
                    if !forceRefresh, EmojiCatalogDiskCache.isFresh(cachedRecord) {
                        self.loadState = .finish
                        self.automaticRetryCount = 0
                        return
                    }
                }
            }

            guard let apiClient = self.apiClient else {
                self.loadState = self.emojis == nil ? .fail : .finish
                return
            }

            do {
                let fetchedEmojis = try await apiClient.fetchCustomEmojis()
                self.emojis = fetchedEmojis

                // Save to cache
                self.saveToCache(fetchedEmojis)

                // Build data structures
                self.buildDataStructures(from: fetchedEmojis)
                self.loadState = .finish
                self.automaticRetryCount = 0
            } catch {
                // If we have cached data, don't fail - just use cache
                if self.emojis == nil {
                    self.loadState = .fail
                    self.scheduleRetry()
                } else {
                    // Use cached data even if network fails
                    self.loadState = .finish
                }
            }
        }
    }

    func applyCustomGroupOrder(_ orderedGroups: [String]) {
        AppSettings.shared.setEmojiGroupOrder(orderedGroups, for: domain)
        rebuildWithCurrentData()
    }

    func resetCustomGroupOrder() {
        AppSettings.shared.resetEmojiGroupOrder(for: domain)
        rebuildWithCurrentData()
    }

    var hasCustomGroupOrder: Bool {
        !AppSettings.shared.emojiGroupOrder(for: domain).isEmpty
    }
    
    private func rebuildWithCurrentData() {
        guard let emojis else {
            orderedGroupNames = []
            emojiDict = [:]
            emojiMapping = [:]
            emojiTrie = nil
            emojiGroups = []
            selectedGroupIndex = 0
            return
        }
        buildDataStructures(from: emojis)
    }

    private func buildDataStructures(from emojis: [CustomEmoji]) {
        // Build emojiDict (grouped by shortcode)
        emojiDict = Dictionary(grouping: emojis, by: { $0.shortcode })

        // Build emojiMapping (shortcode -> URL)
        var mapping: [String: String] = [:]
        for (key, values) in emojiDict ?? [:] {
            guard let emoji = values.first else { continue }
            mapping[key] = emoji.url.absoluteString
        }
        emojiMapping = mapping
        
        let pickerEmojis = Self.emojisVisibleInPicker(from: emojis)

        // Build emojiTrie for picker autocomplete
        var trie = EmojiTrie()
        for emoji in pickerEmojis {
            let key = emoji.shortcode.lowercased()
            trie.insert(key, value: emoji)
        }
        emojiTrie = trie
        
        // Build emoji groups by category
        buildEmojiGroups(from: pickerEmojis)
    }

    static func emojisVisibleInPicker(from emojis: [CustomEmoji]) -> [CustomEmoji] {
        emojis.filter(\.visibleInPicker)
    }
    
    private func buildEmojiGroups(from emojis: [CustomEmoji]) {
        let selectedGroupName = currentGroupName

        guard !emojis.isEmpty else {
            orderedGroupNames = []
            emojiGroups = []
            selectedGroupIndex = 0
            return
        }

        // Group emojis by category
        let grouped = Dictionary(grouping: emojis) { emoji -> String in
            emoji.category ?? MoroL10n.EmojiL10n.categoryOther
        }

        let storedOrder = AppSettings.shared.emojiGroupOrder(for: domain)
        var orderingMap: [String: Int] = [:]
        for (index, category) in storedOrder.enumerated() where orderingMap[category] == nil {
            orderingMap[category] = index
        }

        let sortedCategories = grouped.keys.sorted { lhs, rhs in
            let lhsOrder = orderingMap[lhs] ?? Int.max
            let rhsOrder = orderingMap[rhs] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        orderedGroupNames = sortedCategories
        emojiGroups = sortedCategories.map { category in
            EmojiGroup(
                name: category,
                emojis: grouped[category] ?? []
            )
        }

        // A cache-to-network refresh can reorder categories. Preserve the
        // selected category by stable name instead of retaining a stale index.
        if let selectedGroupName,
           let refreshedIndex = emojiGroups.firstIndex(where: { $0.name == selectedGroupName }) {
            selectedGroupIndex = refreshedIndex
        } else if selectedGroupIndex >= emojiGroups.count {
            selectedGroupIndex = 0
        }
    }
    
    func selectGroup(at index: Int) {
        guard index >= 0 && index < emojiGroups.count else { return }
        selectedGroupIndex = index
    }
    
    var currentGroupEmojis: [CustomEmoji] {
        guard selectedGroupIndex < emojiGroups.count else { return [] }
        return emojiGroups[selectedGroupIndex].emojis
    }

    private var currentGroupName: String? {
        guard selectedGroupIndex < emojiGroups.count else { return nil }
        return emojiGroups[selectedGroupIndex].name
    }
}

// MARK: - Emoji Group

struct EmojiGroup: Identifiable {
    let name: String
    let emojis: [CustomEmoji]

    var id: String { name }
}

/// Simple Trie structure for emoji autocomplete
struct EmojiTrie {
    private class Node {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        var children: [Character: Node] = [:]
        var value: CustomEmoji?
    }
    
    private let root = Node()
    
    mutating func insert(_ key: String, value: CustomEmoji) {
        var current = root
        for char in key {
            if current.children[char] == nil {
                current.children[char] = Node()
            }
            current = current.children[char]!
        }
        current.value = value
    }
    
    func search(_ prefix: String) -> [CustomEmoji] {
        var current = root
        for char in prefix.lowercased() {
            guard let next = current.children[char] else {
                return []
            }
            current = next
        }
        
        // Collect all emojis with this prefix
        var results: [CustomEmoji] = []
        collectEmojis(from: current, into: &results)
        return results
    }
    
    private func collectEmojis(from node: Node, into results: inout [CustomEmoji]) {
        if let value = node.value {
            results.append(value)
        }
        for child in node.children.values {
            collectEmojis(from: child, into: &results)
        }
    }
}
