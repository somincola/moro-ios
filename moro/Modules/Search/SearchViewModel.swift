//
//  SearchViewModel.swift
//  moro
//
//  Shared production search state used by UIKit and covered by unit tests.
//

import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    enum Scope: Int, CaseIterable, Hashable, Codable {
        case all
        case accounts
        case statuses
        case hashtags

        var title: String {
            switch self {
            case .all: return MoroL10n.Search.tabAll
            case .accounts: return MoroL10n.Search.tabAccounts
            case .statuses: return MoroL10n.Search.tabStatuses
            case .hashtags: return MoroL10n.Search.tabHashtags
            }
        }

        var apiType: MastodonSearchType? {
            switch self {
            case .all: return nil
            case .accounts: return .accounts
            case .statuses: return .statuses
            case .hashtags: return .hashtags
            }
        }
    }

    private struct Configuration {
        let initialPageSize: Int
        let paginationPageSize: Int
        let cacheTTL: TimeInterval
        let cacheMaxEntries: Int

        static let production = Configuration(
            initialPageSize: 20,
            paginationPageSize: 40,
            cacheTTL: 120,
            cacheMaxEntries: 36
        )
    }

    @Published var query: String
    @Published var scope: Scope = .all
    @Published private(set) var results = SearchResults()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreResults = false
    @Published private(set) var loadMoreFailed = false
    @Published private(set) var hasSearchedCurrentQuery = false

    var onStateChange: (() -> Void)?
    var onResultsReceived: ((SearchResults) -> Void)?

    private struct CacheKey: Hashable {
        let query: String
        let scope: Scope
    }

    private struct CachedResult {
        let results: SearchResults
        let hasMoreResults: Bool
        let nextOffset: Int
        let cachedAt: Date
    }

    private let apiClient: MastodonAPI
    private let configuration: Configuration

    private var currentOffset = 0
    private var lastCommittedQuery = ""
    private var lastCommittedScope: Scope = .all
    private var activeRequestID = UUID()
    private var queryTask: Task<Void, Never>?
    private var resultCache: [CacheKey: CachedResult] = [:]
    private var resultCacheOrder: [CacheKey] = []

    init(apiClient: MastodonAPI, initialQuery: String? = nil) {
        self.apiClient = apiClient
        self.configuration = .production
        self.query = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    deinit {
        queryTask?.cancel()
    }

    func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearState(scope: scope)
            return
        }

        query = trimmed
        lastCommittedQuery = trimmed
        lastCommittedScope = scope
        loadMoreFailed = false

        if let cached = cachedResult(query: trimmed, scope: scope) {
            applyCachedSnapshot(cached, query: trimmed, scope: scope)
        } else {
            results = SearchResults()
            errorMessage = nil
            currentOffset = 0
            hasMoreResults = false
            hasSearchedCurrentQuery = false
            isLoading = true
            isLoadingMore = false
        }

        notifyStateChanged()
        runSearch(
            query: trimmed,
            scope: scope,
            offset: 0,
            limit: configuration.initialPageSize,
            append: false
        )
    }

    func loadMoreIfNeeded() {
        guard scope != .all else { return }
        guard !isLoading, !isLoadingMore, !loadMoreFailed, hasMoreResults else { return }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed == lastCommittedQuery, scope == lastCommittedScope else { return }

        isLoadingMore = true
        loadMoreFailed = false
        notifyStateChanged()
        runSearch(
            query: trimmed,
            scope: scope,
            offset: currentOffset,
            limit: configuration.paginationPageSize,
            append: true
        )
    }

    func retryLoadMore() {
        guard loadMoreFailed else { return }
        loadMoreFailed = false
        hasMoreResults = true
        loadMoreIfNeeded()
    }

    func markTyping(query: String, scope: Scope, keepResults: Bool = true) {
        invalidateActiveRequest()
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        if !keepResults {
            results = SearchResults()
        }
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
        hasMoreResults = false
        loadMoreFailed = false
        currentOffset = 0
        hasSearchedCurrentQuery = false
        notifyStateChanged()
    }

    func prepareForManualSearch(scope: Scope, keepResults: Bool) {
        markTyping(query: query, scope: scope, keepResults: keepResults)
    }

    func clearState(scope: Scope) {
        invalidateActiveRequest()
        query = ""
        self.scope = scope
        results = SearchResults()
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
        hasMoreResults = false
        loadMoreFailed = false
        currentOffset = 0
        lastCommittedQuery = ""
        lastCommittedScope = scope
        hasSearchedCurrentQuery = false
        notifyStateChanged()
    }

    func applyCachedResults(query: String, scope: Scope) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cached = cachedResult(query: trimmed, scope: scope)
            ?? deriveScopedResultFromAllCache(query: trimmed, scope: scope)
        guard let cached else { return false }

        self.query = trimmed
        self.scope = scope
        cacheResult(
            query: trimmed,
            scope: scope,
            results: cached.results,
            hasMoreResults: cached.hasMoreResults,
            nextOffset: cached.nextOffset
        )
        applyCachedSnapshot(cached, query: trimmed, scope: scope)
        notifyStateChanged()
        return true
    }

    func clearCache() {
        resultCache.removeAll()
        resultCacheOrder.removeAll()
    }

    func cancel() {
        invalidateActiveRequest()
    }

    private func runSearch(
        query: String,
        scope: Scope,
        offset: Int,
        limit: Int,
        append: Bool
    ) {
        invalidateActiveRequest()
        let requestID = UUID()
        activeRequestID = requestID
        let apiClient = apiClient

        queryTask = Task { [weak self] in
            do {
                let response = try await apiClient.search(
                    query: query,
                    type: scope.apiType,
                    resolve: true,
                    limit: limit,
                    offset: offset
                )
                guard !Task.isCancelled, let self, requestID == self.activeRequestID else { return }
                self.applySuccessfulResponse(
                    response,
                    query: query,
                    scope: scope,
                    offset: offset,
                    limit: limit,
                    append: append
                )
            } catch {
                guard !Task.isCancelled, let self, requestID == self.activeRequestID else { return }
                self.applyFailure(error, append: append)
            }
        }
    }

    private func applySuccessfulResponse(
        _ response: SearchResults,
        query: String,
        scope: Scope,
        offset: Int,
        limit: Int,
        append: Bool
    ) {
        let previousTotal = append ? totalCount(in: results, for: scope) : 0
        let merged = append ? mergeResults(base: results, incoming: response) : response
        let currentPageCount = pageCount(in: response, for: scope)
        let hasServerMore = scope != .all && currentPageCount >= limit

        results = merged
        if append {
            let appendedCount = max(totalCount(in: merged, for: scope) - previousTotal, 0)
            hasMoreResults = hasServerMore && appendedCount > 0
        } else {
            hasMoreResults = hasServerMore
        }
        if hasMoreResults {
            currentOffset = offset + limit
        }

        cacheResult(
            query: query,
            scope: scope,
            results: merged,
            hasMoreResults: hasMoreResults,
            nextOffset: currentOffset
        )
        errorMessage = nil
        loadMoreFailed = false
        hasSearchedCurrentQuery = true
        isLoading = false
        isLoadingMore = false
        onResultsReceived?(response)
        notifyStateChanged()
    }

    private func applyFailure(_ error: Error, append: Bool) {
        errorMessage = error.localizedDescription
        if append {
            loadMoreFailed = true
        } else {
            results = SearchResults()
        }
        hasSearchedCurrentQuery = true
        isLoading = false
        isLoadingMore = false
        notifyStateChanged()
    }

    private func applyCachedSnapshot(_ cached: CachedResult, query: String, scope: Scope) {
        lastCommittedQuery = query
        lastCommittedScope = scope
        results = cached.results
        errorMessage = nil
        currentOffset = cached.nextOffset
        hasMoreResults = scope == .all ? false : cached.hasMoreResults
        loadMoreFailed = false
        hasSearchedCurrentQuery = true
        isLoading = false
        isLoadingMore = false
    }

    private func invalidateActiveRequest() {
        queryTask?.cancel()
        queryTask = nil
        activeRequestID = UUID()
    }

    private func notifyStateChanged() {
        onStateChange?()
    }

    private func pageCount(in response: SearchResults, for scope: Scope) -> Int {
        switch scope {
        case .all:
            return max(response.accounts.count, response.statuses.count, response.hashtags.count)
        case .accounts:
            return response.accounts.count
        case .statuses:
            return response.statuses.count
        case .hashtags:
            return response.hashtags.count
        }
    }

    private func totalCount(in response: SearchResults, for scope: Scope) -> Int {
        switch scope {
        case .all:
            return response.accounts.count + response.statuses.count + response.hashtags.count
        case .accounts:
            return response.accounts.count
        case .statuses:
            return response.statuses.count
        case .hashtags:
            return response.hashtags.count
        }
    }

    private func mergeResults(base: SearchResults, incoming: SearchResults) -> SearchResults {
        SearchResults(
            accounts: mergeAccounts(base.accounts, incoming.accounts),
            statuses: mergeStatuses(base.statuses, incoming.statuses),
            hashtags: mergeTags(base.hashtags, incoming.hashtags)
        )
    }

    private func mergeAccounts(_ existing: [Account], _ incoming: [Account]) -> [Account] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for account in incoming where !seen.contains(account.id) {
            merged.append(account)
            seen.insert(account.id)
        }
        return merged
    }

    private func mergeStatuses(_ existing: [Status], _ incoming: [Status]) -> [Status] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for status in incoming where !seen.contains(status.id) {
            merged.append(status)
            seen.insert(status.id)
        }
        return merged
    }

    private func mergeTags(_ existing: [SearchTag], _ incoming: [SearchTag]) -> [SearchTag] {
        var seen = Set(existing.map { $0.name.lowercased() })
        var merged = existing
        for tag in incoming {
            let key = tag.name.lowercased()
            guard !seen.contains(key) else { continue }
            merged.append(tag)
            seen.insert(key)
        }
        return merged
    }

    private func cacheKey(query: String, scope: Scope) -> CacheKey {
        CacheKey(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            scope: scope
        )
    }

    private func cachedResult(query: String, scope: Scope) -> CachedResult? {
        pruneExpiredCacheEntries()
        let key = cacheKey(query: query, scope: scope)
        guard let cached = resultCache[key] else { return nil }
        if Date().timeIntervalSince(cached.cachedAt) > configuration.cacheTTL {
            removeCachedResult(for: key)
            return nil
        }
        touchCacheKey(key)
        return cached
    }

    private func deriveScopedResultFromAllCache(query: String, scope: Scope) -> CachedResult? {
        guard scope != .all else { return nil }
        guard let allCached = cachedResult(query: query, scope: .all) else { return nil }

        let scopedResults: SearchResults
        switch scope {
        case .all:
            return nil
        case .accounts:
            scopedResults = SearchResults(accounts: allCached.results.accounts)
        case .statuses:
            scopedResults = SearchResults(statuses: allCached.results.statuses)
        case .hashtags:
            scopedResults = SearchResults(hashtags: allCached.results.hashtags)
        }

        let scopedCount = pageCount(in: scopedResults, for: scope)
        return CachedResult(
            results: scopedResults,
            hasMoreResults: scopedCount >= configuration.initialPageSize,
            nextOffset: scopedCount,
            cachedAt: Date()
        )
    }

    private func cacheResult(
        query: String,
        scope: Scope,
        results: SearchResults,
        hasMoreResults: Bool,
        nextOffset: Int
    ) {
        pruneExpiredCacheEntries()
        let key = cacheKey(query: query, scope: scope)
        resultCache[key] = CachedResult(
            results: results,
            hasMoreResults: hasMoreResults,
            nextOffset: nextOffset,
            cachedAt: Date()
        )
        touchCacheKey(key)
        trimCacheIfNeeded()
    }

    private func touchCacheKey(_ key: CacheKey) {
        if let index = resultCacheOrder.firstIndex(of: key) {
            resultCacheOrder.remove(at: index)
        }
        resultCacheOrder.append(key)
    }

    private func removeCachedResult(for key: CacheKey) {
        resultCache.removeValue(forKey: key)
        if let index = resultCacheOrder.firstIndex(of: key) {
            resultCacheOrder.remove(at: index)
        }
    }

    private func pruneExpiredCacheEntries() {
        guard !resultCache.isEmpty else { return }
        let now = Date()
        let expiredKeys = resultCache.compactMap { key, value in
            now.timeIntervalSince(value.cachedAt) > configuration.cacheTTL ? key : nil
        }
        for key in expiredKeys {
            removeCachedResult(for: key)
        }
    }

    private func trimCacheIfNeeded() {
        let overflow = resultCacheOrder.count - configuration.cacheMaxEntries
        guard overflow > 0 else { return }
        let keysToRemove = Array(resultCacheOrder.prefix(overflow))
        for key in keysToRemove {
            removeCachedResult(for: key)
        }
    }
}
