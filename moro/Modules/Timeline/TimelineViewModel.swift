//
//  TimelineViewModel.swift
//  moro
//
//  Manages timeline state and data fetching.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TimelineViewModel: ObservableObject, FeedCoordinatorUpdatable {
    struct BootstrapConfig: Sendable, Equatable {
        enum DeviceTier: String, Sendable {
            case constrained
            case balanced
            case performance
        }

        let initialLoadLimit: Int
        let refreshLoadLimit: Int
        let paginationLoadLimit: Int
        let initialRenderCap: Int
        let cacheHydrationSoftTimeoutNanoseconds: UInt64
        let deferredFillBatchSize: Int
        let deferredFillStepNanoseconds: UInt64
        let deferredFillInitialDelayNanoseconds: UInt64

        nonisolated static let constrainedConfig = BootstrapConfig(
            initialLoadLimit: 20,
            refreshLoadLimit: 20,
            paginationLoadLimit: 40,
            initialRenderCap: 18,
            cacheHydrationSoftTimeoutNanoseconds: 180_000_000,
            deferredFillBatchSize: 4,
            deferredFillStepNanoseconds: 150_000_000,
            deferredFillInitialDelayNanoseconds: 380_000_000
        )

        nonisolated static let balancedConfig = BootstrapConfig(
            initialLoadLimit: 20,
            refreshLoadLimit: 20,
            paginationLoadLimit: 40,
            initialRenderCap: 24,
            cacheHydrationSoftTimeoutNanoseconds: 220_000_000,
            deferredFillBatchSize: 6,
            deferredFillStepNanoseconds: 120_000_000,
            deferredFillInitialDelayNanoseconds: 320_000_000
        )

        nonisolated static let performanceConfig = BootstrapConfig(
            initialLoadLimit: 20,
            refreshLoadLimit: 20,
            paginationLoadLimit: 40,
            initialRenderCap: 24,
            cacheHydrationSoftTimeoutNanoseconds: 240_000_000,
            deferredFillBatchSize: 8,
            deferredFillStepNanoseconds: 90_000_000,
            deferredFillInitialDelayNanoseconds: 260_000_000
        )

        nonisolated static let defaultConfig = balancedConfig

        nonisolated static func detectDeviceTier(
            processInfo: ProcessInfo = .processInfo
        ) -> DeviceTier {
            let memoryGB = Double(processInfo.physicalMemory) / 1_073_741_824
            let cores = processInfo.activeProcessorCount

            if memoryGB <= 3.6 || cores <= 4 {
                return .constrained
            }
            if memoryGB >= 7.6 && cores >= 6 {
                return .performance
            }
            return .balanced
        }

        nonisolated static func adaptiveDefault(
            processInfo: ProcessInfo = .processInfo
        ) -> BootstrapConfig {
            switch detectDeviceTier(processInfo: processInfo) {
            case .constrained:
                return constrainedConfig
            case .balanced:
                return balancedConfig
            case .performance:
                return performanceConfig
            }
        }
    }

    enum LoadingState {
        case idle
        case loading
        case refreshing
        case loadingMore
        case error(Error)
    }

    enum InitialLoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    enum RefreshTrigger: Sendable {
        case pull
        case tabRetap
        case newPosts
        case foreground
        case compose
    }

    enum RefreshResult {
        case success(insertedCount: Int, replacedTimeline: Bool)
        case failure(Error)
        case cancelled

        var succeeded: Bool {
            if case .success = self { return true }
            return false
        }
    }

    enum RefreshState {
        case idle
        case refreshing(RefreshTrigger)
        case failed(Error)
    }

    enum PaginationState {
        case idle
        case loading
        case failed(Error)
        case exhausted
    }

    @Published var statuses: [Status] = []
    @Published private(set) var initialLoadState: InitialLoadState = .idle
    @Published private(set) var refreshState: RefreshState = .idle
    @Published private(set) var paginationState: PaginationState = .idle
    @Published var hasMore: Bool = true
    @Published var timelineType: TimelineType = .home

    // MARK: - Marker (Reading Position) Support

    /// Last read status ID (from server marker)
    @Published private(set) var lastReadStatusID: String?

    /// Index of the current top visible status (for marker saving)
    @Published var currentTopVisibleStatusID: String?

    /// Whether there are unread statuses above the current position
    @Published private(set) var hasUnreadAbove: Bool = false

    /// Debounce timer for saving marker position
    private var markerSaveTask: Task<Void, Never>?
    private let markerSaveDebounceInterval: TimeInterval = 3.0

    // MARK: - Stream (Real-time Updates) Support

    /// Pending new status IDs detected via stream (only IDs, not full Status objects)
    @Published private(set) var pendingNewStatusIDs: Set<String> = []
    @Published private(set) var pendingCreatedStatuses: [Status] = []

    private let apiClient: MastodonAPI
    private var currentMaxID: String?
    private var currentSinceID: String?
    private var cancellables = Set<AnyCancellable>()

    /// Shared account cache for user info lookup
    let accountCache: AccountCache
    private let feedCoordinator: FeedCoordinator
    private let timelineCache: TimelineCache
    private let cacheClientID: String

    /// Track last load more trigger time to prevent rapid firing
    private var lastLoadMoreTime: Date?
    private let loadMoreThrottleInterval: TimeInterval = 0.5  // 500ms throttle
    private let bootstrapConfig: BootstrapConfig
    private var deferredInitialFillTask: Task<Void, Never>?
    private var deferredInitialStatusIDs: Set<String> = []
    private var deferredStatusUpdates: [String: Status] = [:]
    private var deferredDeletedStatusIDs: Set<String> = []

    /// Track which status IDs have already triggered loadMore to prevent duplicate triggers
    private var triggeredLoadMoreForStatusIDs: Set<String> = []

    private var activeRefreshRequest: (id: UUID, task: Task<RefreshResult, Never>)?
    private var activeLoadMoreRequest: (id: UUID, task: Task<Void, Never>)?
    private let maximumCatchUpPages = 10

    private static let enableTimelineDebugLogging = false

    var loadingState: LoadingState {
        if case .loading = initialLoadState, statuses.isEmpty {
            return .loading
        }
        if case .refreshing = refreshState {
            return .refreshing
        }
        if case .loading = paginationState {
            return .loadingMore
        }
        if statuses.isEmpty {
            if case .failed(let error) = initialLoadState {
                return .error(error)
            }
            if case .failed(let error) = refreshState {
                return .error(error)
            }
        }
        return .idle
    }

    var loadMoreFailed: Bool {
        if case .failed = paginationState { return true }
        return false
    }

    var isRefreshing: Bool {
        if case .refreshing = refreshState { return true }
        return false
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        guard Self.enableTimelineDebugLogging else { return }
        AppLogger.debug(message(), enabled: Self.enableTimelineDebugLogging)
    }

    var bootstrapTierLabel: String {
        switch bootstrapConfig {
        case .constrainedConfig:
            return BootstrapConfig.DeviceTier.constrained.rawValue
        case .balancedConfig:
            return BootstrapConfig.DeviceTier.balanced.rawValue
        case .performanceConfig:
            return BootstrapConfig.DeviceTier.performance.rawValue
        default:
            return "custom"
        }
    }

    var bootstrapProfileSummary: String {
        "initial=\(bootstrapConfig.initialLoadLimit)/\(bootstrapConfig.initialRenderCap) refresh=\(bootstrapConfig.refreshLoadLimit) page=\(bootstrapConfig.paginationLoadLimit) defer=\(bootstrapConfig.deferredFillBatchSize)x\(bootstrapConfig.deferredFillStepNanoseconds / 1_000_000)ms"
    }

    init(
        apiClient: MastodonAPI, timelineType: TimelineType = .home,
        accountCache: AccountCache? = nil,
        feedCoordinator: FeedCoordinator? = nil,
        timelineCache: TimelineCache? = nil,
        cacheClientID: String = "active-session",
        bootstrapConfig: BootstrapConfig = .adaptiveDefault()
    ) {
        self.apiClient = apiClient
        self.timelineType = timelineType
        self.feedCoordinator = feedCoordinator ?? .shared
        self.timelineCache = timelineCache ?? CacheManager.shared.timelineCache
        self.cacheClientID = cacheClientID
        self.bootstrapConfig = bootstrapConfig
        // Use provided cache or fall back to shared instance
        self.accountCache = accountCache ?? CacheManager.shared.accountCache

        // Listen to feed coordinator updates
        self.feedCoordinator.updates
            .sink { [weak self] update in
                self?.incorporateUpdate(update)
            }
            .store(in: &cancellables)

        // Observe currentTopVisibleStatusID changes and debounce marker saves
        $currentTopVisibleStatusID
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] statusID in
                self?.scheduleMarkerSave(statusID: statusID)
            }
            .store(in: &cancellables)
    }

    func loadInitial() async {
        if case .loading = initialLoadState {
            return
        }
        if case .loaded = initialLoadState, !statuses.isEmpty {
            await resumeCachedContentIfNeeded()
            return
        }

        deferredInitialFillTask?.cancel()
        initialLoadState = .loading
        let hydrationTask = Task { [weak self] in
            guard let self else { return false }
            return await self.hydrateFromCacheIfAvailable()
        }
        let hydratedFromCache = await awaitCacheHydrationResult(from: hydrationTask)
        let cachedStatusesBeforeNetwork = await loadCachedStatusesSnapshot()

        do {
            let newStatuses: [Status]
            switch timelineType {
            case .home:
                newStatuses = try await apiClient.fetchHomeTimeline(
                    maxID: nil, sinceID: nil, limit: bootstrapConfig.initialLoadLimit)
            case .local:
                newStatuses = try await apiClient.fetchPublicTimeline(
                    local: true, maxID: nil, sinceID: nil, minID: nil,
                    limit: bootstrapConfig.initialLoadLimit)
            case .federated:
                newStatuses = try await apiClient.fetchPublicTimeline(
                    local: false, maxID: nil, sinceID: nil, minID: nil,
                    limit: bootstrapConfig.initialLoadLimit)
            case .list(let listID, _):
                newStatuses = try await apiClient.fetchListTimeline(
                    id: listID, maxID: nil, sinceID: nil,
                    limit: bootstrapConfig.initialLoadLimit)
            }

            let cachedStatusesForMerge: [Status]
            if hydratedFromCache, !cachedStatusesBeforeNetwork.isEmpty {
                cachedStatusesForMerge = cachedStatusesBeforeNetwork
            } else {
                cachedStatusesForMerge = await loadCachedStatusesSnapshot()
            }
            let mergedStatuses =
                cachedStatusesForMerge.isEmpty
                ? newStatuses
                : mergeInitialNetworkStatuses(newStatuses, withCached: cachedStatusesForMerge)

            let initialStatuses = Array(mergedStatuses.prefix(bootstrapConfig.initialRenderCap))
            let deferredStatuses = Array(
                mergedStatuses.dropFirst(bootstrapConfig.initialRenderCap)
            )
            deferredInitialFillTask?.cancel()
            statuses = initialStatuses
            currentMaxID = initialStatuses.last?.id
            currentSinceID = initialStatuses.first?.id
            initialLoadState = .loaded
            refreshState = .idle
            hasMore =
                newStatuses.count >= bootstrapConfig.initialLoadLimit
                || mergedStatuses.count > initialStatuses.count
                || mergedStatuses.count >= bootstrapConfig.initialLoadLimit

            // Cache accounts from loaded statuses
            accountCache.cacheFromStatuses(initialStatuses)
            // Persist the full merged snapshot before rendering it in small batches.
            // Switching sources during that fill must not truncate the offline tail.
            if let filter = timelineCacheFilter {
                await timelineCache.set(statuses: mergedStatuses, for: cacheClientID, filter: filter)
            }
            if !deferredStatuses.isEmpty {
                scheduleDeferredInitialFill(with: deferredStatuses)
            } else {
                deferredInitialFillTask = nil
            }
        } catch {
            // Keep cached timeline usable when first network backfill fails.
            let cachedFallbackStatuses: [Status]
            if hydratedFromCache, !cachedStatusesBeforeNetwork.isEmpty {
                cachedFallbackStatuses = cachedStatusesBeforeNetwork
            } else {
                cachedFallbackStatuses = await loadCachedStatusesSnapshot()
            }

            if !cachedFallbackStatuses.isEmpty {
                deferredInitialFillTask?.cancel()
                statuses = Array(cachedFallbackStatuses.prefix(bootstrapConfig.initialRenderCap))
                currentMaxID = statuses.last?.id
                currentSinceID = statuses.first?.id
                hasMore = cachedFallbackStatuses.count >= bootstrapConfig.initialLoadLimit
                    || cachedFallbackStatuses.count > statuses.count
                initialLoadState = .loaded
                refreshState = .failed(error)
                scheduleDeferredInitialFill(with: Array(cachedFallbackStatuses.dropFirst(statuses.count)))
            } else {
                initialLoadState = .failed(error)
            }
        }
    }

    private struct CatchUpBatch {
        let statuses: [Status]
        let reachedExistingTimeline: Bool
    }

    @discardableResult
    func refresh(trigger: RefreshTrigger = .pull) async -> RefreshResult {
        if let activeRefreshRequest {
            return await activeRefreshRequest.task.value
        }

        if let activeLoadMoreRequest {
            activeLoadMoreRequest.task.cancel()
            await activeLoadMoreRequest.task.value
        }

        let requestID = UUID()
        let task = Task { [weak self] in
            guard let self else { return RefreshResult.cancelled }
            return await self.performRefresh(trigger: trigger)
        }
        activeRefreshRequest = (requestID, task)

        let result = await task.value
        if activeRefreshRequest?.id == requestID {
            activeRefreshRequest = nil
        }
        return result
    }

    private func performRefresh(trigger: RefreshTrigger) async -> RefreshResult {
        refreshState = .refreshing(trigger)
        triggeredLoadMoreForStatusIDs.removeAll()

        do {
            let batch = try await fetchCatchUpBatch()
            try Task.checkCancellation()

            var refreshedStatuses = batch.statuses
            var refreshedIDs = Set(refreshedStatuses.map(\.id))
            for stagedStatus in pendingCreatedStatuses
            where refreshedIDs.insert(stagedStatus.id).inserted {
                let insertionIndex = refreshedStatuses.firstIndex {
                    $0.createdAt < stagedStatus.createdAt
                } ?? refreshedStatuses.endIndex
                refreshedStatuses.insert(stagedStatus, at: insertionIndex)
            }

            let shouldReplaceTimeline =
                !batch.reachedExistingTimeline
                && !statuses.isEmpty
                && !refreshedStatuses.isEmpty
            let insertedCount = refreshedStatuses.count

            if shouldReplaceTimeline {
                discardDeferredContent()
                statuses = refreshedStatuses
                currentMaxID = refreshedStatuses.last?.id
                currentSinceID = refreshedStatuses.first?.id
                hasMore = true
                paginationState = .idle
            } else if !refreshedStatuses.isEmpty {
                let existingIDs = Set(statuses.map(\.id))
                statuses.insert(
                    contentsOf: refreshedStatuses.filter { !existingIDs.contains($0.id) },
                    at: 0
                )
                currentSinceID = statuses.first?.id
            }

            if statuses.isEmpty {
                currentMaxID = nil
                currentSinceID = nil
                hasMore = false
                paginationState = .exhausted
            } else if currentMaxID == nil {
                currentMaxID = statuses.last?.id
            }

            pendingCreatedStatuses.removeAll()
            accountCache.cacheFromStatuses(refreshedStatuses)
            persistCurrentStatusesToCache()
            initialLoadState = .loaded
            refreshState = .idle

            return .success(
                insertedCount: insertedCount,
                replacedTimeline: shouldReplaceTimeline
            )
        } catch is CancellationError {
            refreshState = .idle
            return .cancelled
        } catch {
            refreshState = .failed(error)
            if statuses.isEmpty {
                initialLoadState = .failed(error)
            }
            return .failure(error)
        }
    }

    private func fetchCatchUpBatch() async throws -> CatchUpBatch {
        let baselineID = statuses.first?.id
        let existingIDs = Set(statuses.map(\.id))
        var fetched: [Status] = []
        var fetchedIDs: Set<String> = []
        var maxID: String?
        var reachedExistingTimeline = baselineID == nil

        for _ in 0..<maximumCatchUpPages {
            try Task.checkCancellation()
            let page = try await fetchTimelinePage(
                maxID: maxID,
                sinceID: timelineType == .federated ? nil : baselineID,
                limit: bootstrapConfig.refreshLoadLimit
            )

            if page.isEmpty {
                reachedExistingTimeline = true
                break
            }

            if page.contains(where: { existingIDs.contains($0.id) }) {
                reachedExistingTimeline = true
            }

            for status in page
            where !existingIDs.contains(status.id) && fetchedIDs.insert(status.id).inserted {
                fetched.append(status)
            }

            if baselineID == nil
                || reachedExistingTimeline
                || page.count < bootstrapConfig.refreshLoadLimit
            {
                reachedExistingTimeline = true
                break
            }

            guard let nextMaxID = page.last?.id, nextMaxID != maxID else {
                break
            }
            maxID = nextMaxID
        }

        return CatchUpBatch(
            statuses: fetched,
            reachedExistingTimeline: reachedExistingTimeline
        )
    }

    private func fetchTimelinePage(
        maxID: String?,
        sinceID: String?,
        limit: Int
    ) async throws -> [Status] {
        switch timelineType {
        case .home:
            return try await apiClient.fetchHomeTimeline(
                maxID: maxID,
                sinceID: sinceID,
                limit: limit
            )
        case .local:
            return try await apiClient.fetchPublicTimeline(
                local: true,
                maxID: maxID,
                sinceID: sinceID,
                minID: nil,
                limit: limit
            )
        case .federated:
            return try await apiClient.fetchPublicTimeline(
                local: false,
                maxID: maxID,
                sinceID: nil,
                minID: nil,
                limit: limit
            )
        case .list(let listID, _):
            return try await apiClient.fetchListTimeline(
                id: listID,
                maxID: maxID,
                sinceID: sinceID,
                limit: limit
            )
        }
    }

    func loadMore(triggeredByStatusID: String? = nil) async {
        if let activeLoadMoreRequest {
            await activeLoadMoreRequest.task.value
            return
        }

        guard hasMore, !isRefreshing, let maxID = currentMaxID else { return }
        if case .loading = initialLoadState { return }
        // Finish presenting already-cached posts before asking for an older server page.
        guard deferredInitialFillTask == nil else { return }

        if let statusID = triggeredByStatusID {
            if triggeredLoadMoreForStatusIDs.contains(statusID) {
                return
            }
            triggeredLoadMoreForStatusIDs.insert(statusID)
        }

        let now = Date()
        if let lastTime = lastLoadMoreTime,
            now.timeIntervalSince(lastTime) < loadMoreThrottleInterval
        {
            return
        }
        lastLoadMoreTime = now

        let requestID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadMore(maxID: maxID, triggeredByStatusID: triggeredByStatusID)
        }
        activeLoadMoreRequest = (requestID, task)
        await task.value
        if activeLoadMoreRequest?.id == requestID {
            activeLoadMoreRequest = nil
        }
    }

    private func performLoadMore(maxID: String, triggeredByStatusID: String?) async {
        paginationState = .loading

        do {
            let newStatuses = try await fetchTimelinePage(
                maxID: maxID,
                sinceID: nil,
                limit: bootstrapConfig.paginationLoadLimit
            )
            try Task.checkCancellation()

            let existingIDs = Set(statuses.map { $0.id })
            let uniqueNewStatuses = newStatuses.filter { !existingIDs.contains($0.id) }
            if !newStatuses.isEmpty {
                currentMaxID = newStatuses.last?.id
                hasMore = newStatuses.count >= bootstrapConfig.paginationLoadLimit
                triggeredLoadMoreForStatusIDs.removeAll()

                if !uniqueNewStatuses.isEmpty {
                    statuses.append(contentsOf: uniqueNewStatuses)
                    accountCache.cacheFromStatuses(uniqueNewStatuses)
                    appendStatusesToCache(uniqueNewStatuses)
                }
            } else {
                hasMore = false
            }
            paginationState = hasMore ? .idle : .exhausted
        } catch is CancellationError {
            paginationState = .idle
            if let statusID = triggeredByStatusID {
                triggeredLoadMoreForStatusIDs.remove(statusID)
            }
        } catch {
            paginationState = .failed(error)
            if let statusID = triggeredByStatusID {
                triggeredLoadMoreForStatusIDs.remove(statusID)
            }
        }
    }

    func updateStatus(_ status: Status) {
        if deferredInitialStatusIDs.contains(status.id) {
            deferredStatusUpdates[status.id] = status
            persistSingleStatusUpdateToCache(status)
        }
        if let index = statuses.firstIndex(where: { $0.id == status.id || $0.displayStatus.id == status.id }) {
            let mergedStatus = statuses[index].incorporatingDisplayStatusUpdate(status)
            statuses[index] = mergedStatus
            persistSingleStatusUpdateToCache(mergedStatus)
        }
    }

    func insertCreatedStatus(_ status: Status) {
        guard timelineType == .home else { return }
        guard !statuses.contains(where: { $0.id == status.id }) else { return }

        statuses.insert(status, at: 0)
        currentSinceID = status.id
        if currentMaxID == nil {
            currentMaxID = status.id
        }
        initialLoadState = .loaded
        accountCache.cacheFromStatuses([status])
        persistCurrentStatusesToCache()
    }

    func stageCreatedStatus(_ status: Status) {
        guard timelineType == .home else { return }
        guard !statuses.contains(where: { $0.id == status.id }) else { return }
        guard !pendingCreatedStatuses.contains(where: { $0.id == status.id }) else { return }
        pendingCreatedStatuses.append(status)
    }

    /// Remove a status from the timeline (e.g., after deletion)
    func removeStatus(id: String) {
        if statuses.contains(where: { $0.id == id }) {
            statuses.removeAll { $0.id == id }
        }
        removeStatusFromCache(id: id)
    }

    /// Vote on a poll
    func votePoll(pollID: String, choices: [Int]) async -> Bool {
        do {
            let updatedPoll = try await apiClient.votePoll(pollID: pollID, choices: choices)

            guard let owner = statuses.first(where: { $0.displayStatus.poll?.id == pollID }) else {
                return false
            }
            // updating(poll:) preserves every other field and updates the nested post
            // when the visible poll belongs to a boost wrapper.
            updateStatus(owner.updating(poll: updatedPoll))
            return true
        } catch {
            debugLog("Failed to vote on poll: \(error)")
            return false
        }
    }

    /// Stop background work (the deferred initial fill) without discarding loaded
    /// statuses — called when the user switches away from this timeline so the now
    /// off-screen view model stops appending statuses and writing to the cache.
    func cancelBackgroundTasks() {
        deferredInitialFillTask?.cancel()
        deferredInitialFillTask = nil
    }

    private func discardDeferredContent() {
        cancelBackgroundTasks()
        deferredInitialStatusIDs = []
        deferredStatusUpdates = [:]
        deferredDeletedStatusIDs = []
    }

    func resumeCachedContentIfNeeded() async {
        guard deferredInitialFillTask == nil, !statuses.isEmpty else { return }
        let cached = await loadCachedStatusesSnapshot()
        guard !Task.isCancelled, deferredInitialFillTask == nil else { return }
        let visibleIDs = Set(statuses.map(\.id))
        scheduleDeferredInitialFill(with: cached.filter { !visibleIDs.contains($0.id) })
    }

    /// Clear all statuses and reset state (for timeline switching)
    func clearStatuses() {
        discardDeferredContent()
        activeRefreshRequest?.task.cancel()
        activeRefreshRequest = nil
        activeLoadMoreRequest?.task.cancel()
        activeLoadMoreRequest = nil
        statuses = []
        currentMaxID = nil
        currentSinceID = nil
        initialLoadState = .idle
        refreshState = .idle
        paginationState = .idle
        hasMore = true
        lastLoadMoreTime = nil
        triggeredLoadMoreForStatusIDs.removeAll()
    }

    // MARK: - FeedCoordinatorUpdatable

    func incorporateUpdate(_ update: UpdatedElement) {
        switch update {
        case .createdPost:
            // TimelineHomeView decides whether a created post is revealed immediately
            // or represented by the persistent new-post notice.
            break
        case .post(let updatedStatus):
            updateStatus(updatedStatus)
        case .deletedPost(let deletedID):
            // Only touch the @Published array if this timeline holds the post —
            // removeAll(where:) fires @Published even on no match, re-rendering inactive
            // timelines on every unrelated deletion. Cache removal stays unconditional so a
            // post deleted while this timeline is off-screen is still purged from disk.
            if statuses.contains(where: { $0.id == deletedID }) {
                statuses.removeAll { $0.id == deletedID }
            }
            removeStatusFromCache(id: deletedID)
        case .hashtag, .relationship:
            // Not applicable for timeline
            break
        }
    }

    // MARK: - Marker (Reading Position) API

    /// Fetch the last reading position from the server
    func fetchMarker() async {
        // Only home timeline supports markers
        guard timelineType == .home else { return }

        do {
            let marker = try await apiClient.fetchMarkers(timelines: [.home])
            if let homeMarker = marker.home {
                lastReadStatusID = homeMarker.lastReadId
                updateUnreadState()
                debugLog("📍 [Marker] Fetched last read position: \(homeMarker.lastReadId)")
            }
        } catch {
            debugLog("⚠️ [Marker] Failed to fetch marker: \(error)")
        }
    }

    /// Save the current reading position to the server
    func saveMarker(statusID: String) async {
        // Only home timeline supports markers
        guard timelineType == .home else { return }

        do {
            let _ = try await apiClient.saveMarker(home: statusID, notifications: nil)
            lastReadStatusID = statusID
            updateUnreadState()
            debugLog("📍 [Marker] Saved reading position: \(statusID)")
        } catch {
            debugLog("⚠️ [Marker] Failed to save marker: \(error)")
        }
    }

    /// Schedule a debounced marker save
    private func scheduleMarkerSave(statusID: String) {
        // Only home timeline supports markers
        guard timelineType == .home else { return }

        // Cancel any pending save task
        markerSaveTask?.cancel()

        // Schedule a new save task with debounce
        markerSaveTask = Task {
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(markerSaveDebounceInterval * 1_000_000_000))

                // Check if task was cancelled during the delay
                guard !Task.isCancelled else { return }

                await saveMarker(statusID: statusID)
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    /// Update the unread state based on current position
    private func updateUnreadState() {
        guard let lastReadID = lastReadStatusID else {
            hasUnreadAbove = false
            return
        }

        // Check if there are statuses newer than the last read position
        if let lastReadIndex = statuses.firstIndex(where: { $0.id == lastReadID }) {
            hasUnreadAbove = lastReadIndex > 0
        } else {
            // Last read status not in current list, assume there might be unread
            hasUnreadAbove = !statuses.isEmpty
        }
    }

    /// Scroll to the last read position
    /// Returns the index of the last read status if found, nil otherwise
    func findLastReadIndex() -> Int? {
        guard let lastReadID = lastReadStatusID else { return nil }
        return statuses.firstIndex(where: { $0.id == lastReadID })
    }

    /// Mark all statuses as read (scroll to top)
    func markAllAsRead() {
        guard let firstStatusID = statuses.first?.id else { return }
        currentTopVisibleStatusID = firstStatusID
        hasUnreadAbove = false
    }

    // MARK: - Stream (Real-time Updates) Handling

    /// Handle a stream event.
    /// NOTE: `.update` events are now counted by `TimelineDetectionManager`;
    /// the View dispatches to `trackPendingStatusID(_:)` when the policy allows.
    func handleStreamEvent(_ event: StreamEvent) {
        switch event {
        case .update:
            // New-post counting is managed by TimelineDetectionManager.
            // TimelineHomeView calls trackPendingStatusID when detection scope and banner are active.
            break
        case .statusUpdate(let status):
            updateStatus(status)
        case .delete(let statusId):
            removeStatus(id: statusId)
        case .notification, .conversation:
            // Not handled by TimelineViewModel
            break
        }
    }

    /// Upper bound on the lightweight pending-new-post set. A hyperactive stream can emit
    /// thousands of posts while the user ignores the "new posts" banner; past this point the
    /// exact count no longer matters and fetchNewStatuses() pulls the real newest posts by
    /// sinceID regardless — so we stop growing the set instead of leaking IDs unboundedly.
    private static let maxPendingStatusIDs = 200

    /// Track a status ID as pending without storing the full Status object.
    /// The full statuses are fetched from API when the user taps the banner.
    func trackPendingStatusID(_ id: String) {
        guard !statuses.contains(where: { $0.id == id }) else { return }
        guard pendingNewStatusIDs.count < Self.maxPendingStatusIDs else { return }
        guard pendingNewStatusIDs.insert(id).inserted else { return }

    }

    /// Fetch and insert new statuses when user confirms (banner tap / refresh).
    /// Full statuses are fetched entirely from the API — no locally cached Status objects needed.
    @discardableResult
    func fetchNewStatuses(
        force: Bool = false,
        providesFeedback: Bool = true
    ) async -> Bool {
        guard force || !pendingNewStatusIDs.isEmpty else { return false }

        if providesFeedback {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }

        let result = await refresh(trigger: .newPosts)
        guard result.succeeded else {
            return false
        }

        pendingNewStatusIDs.removeAll()

        if providesFeedback {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        return true
    }

    /// Clear pending statuses without inserting (e.g., when switching timelines or refreshing)
    func clearPendingStatuses() {
        pendingNewStatusIDs.removeAll()
        pendingCreatedStatuses.removeAll()
    }
}

extension TimelineViewModel {
    fileprivate var timelineCacheFilter: TimelineFilter? {
        switch timelineType {
        case .home:
            return .home
        case .local:
            return .local
        case .federated:
            return .federated
        case .list(let id, _):
            return .list(id: id)
        }
    }

    fileprivate func hydrateFromCacheIfAvailable() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard statuses.isEmpty else { return false }
        guard let cacheFilter = timelineCacheFilter else { return false }
        guard
            let cached = await timelineCache.getStatuses(
                for: cacheClientID,
                filter: cacheFilter
            ), !cached.isEmpty
        else { return false }
        guard !Task.isCancelled else { return false }

        let initialCached = Array(cached.prefix(bootstrapConfig.initialRenderCap))
        let deferredCached = Array(cached.dropFirst(bootstrapConfig.initialRenderCap))

        statuses = initialCached
        currentMaxID = initialCached.last?.id
        currentSinceID = initialCached.first?.id
        hasMore = true
        accountCache.cacheFromStatuses(initialCached)
        scheduleDeferredInitialFill(with: deferredCached)
        return true
    }

    fileprivate func awaitCacheHydrationResult(from task: Task<Bool, Never>) async -> Bool {
        let timeout = bootstrapConfig.cacheHydrationSoftTimeoutNanoseconds
        let result = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await task.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeout)
                return false
            }
            let firstCompleted = await group.next() ?? false
            group.cancelAll()
            return firstCompleted
        }

        if !result {
            task.cancel()
        }
        return result
    }

    fileprivate func loadCachedStatusesSnapshot() async -> [Status] {
        guard let cacheFilter = timelineCacheFilter else { return [] }
        guard
            let cached = await timelineCache.getStatuses(
                for: cacheClientID,
                filter: cacheFilter
            ), !cached.isEmpty
        else { return [] }
        return cached
    }

    fileprivate func mergeInitialNetworkStatuses(_ network: [Status], withCached cached: [Status])
        -> [Status]
    {
        guard !cached.isEmpty else { return network }
        guard !network.isEmpty else { return cached }

        let networkIDs = Set(network.map(\.id))
        return network + cached.filter { !networkIDs.contains($0.id) }
    }

    fileprivate func persistCurrentStatusesToCache() {
        guard let snapshotFilter = timelineCacheFilter else { return }
        let statusesSnapshot = statuses
        let snapshotClientID = self.cacheClientID
        let timelineCache = self.timelineCache
        let preservesUnrenderedTail = !deferredInitialStatusIDs.isEmpty
        Task(priority: .utility) {
            if preservesUnrenderedTail {
                await timelineCache.prepend(statuses: statusesSnapshot, for: snapshotClientID, filter: snapshotFilter)
            } else {
                await timelineCache.set(statuses: statusesSnapshot, for: snapshotClientID, filter: snapshotFilter)
            }
        }
    }

    fileprivate func appendStatusesToCache(_ newStatuses: [Status]) {
        guard !newStatuses.isEmpty else { return }
        guard let snapshotFilter = timelineCacheFilter else { return }
        let snapshotClientID = self.cacheClientID
        let timelineCache = self.timelineCache
        Task(priority: .utility) {
            await timelineCache.append(
                statuses: newStatuses,
                for: snapshotClientID,
                filter: snapshotFilter
            )
        }
    }

    fileprivate func scheduleDeferredInitialFill(with deferredStatuses: [Status]) {
        deferredInitialStatusIDs = Set(deferredStatuses.flatMap { [$0.id, $0.displayStatus.id] })
        deferredStatusUpdates = deferredStatusUpdates.filter { deferredInitialStatusIDs.contains($0.key) }
        deferredDeletedStatusIDs.formIntersection(deferredInitialStatusIDs)
        guard !deferredStatuses.isEmpty else { return }
        deferredInitialFillTask?.cancel()
        deferredInitialFillTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.bootstrapConfig.deferredFillInitialDelayNanoseconds)
            guard !Task.isCancelled else { return }
            var existingIDs = Set(self.statuses.map(\.id))
            let appendable = deferredStatuses.filter { status in
                if existingIDs.contains(status.id) {
                    return false
                }
                existingIDs.insert(status.id)
                return true
            }
            guard !appendable.isEmpty else {
                self.deferredInitialFillTask = nil
                self.deferredInitialStatusIDs = []
                self.deferredStatusUpdates = [:]
                self.deferredDeletedStatusIDs = []
                return
            }

            var cursor = 0
            while cursor < appendable.count {
                guard !Task.isCancelled else { return }
                let nextCursor = min(cursor + self.bootstrapConfig.deferredFillBatchSize, appendable.count)
                let presentIDs = Set(self.statuses.map(\.id))
                let chunk = appendable[cursor..<nextCursor].filter {
                    !presentIDs.contains($0.id) && !self.deferredDeletedStatusIDs.contains($0.id)
                        && !self.deferredDeletedStatusIDs.contains($0.displayStatus.id)
                }.map { status in
                    self.deferredStatusUpdates[status.displayStatus.id].map {
                        status.incorporatingDisplayStatusUpdate($0)
                    } ?? status
                }
                self.statuses.append(contentsOf: chunk)
                self.currentMaxID = self.statuses.last?.id
                self.accountCache.cacheFromStatuses(chunk)
                cursor = nextCursor

                if cursor < appendable.count {
                    try? await Task.sleep(nanoseconds: self.bootstrapConfig.deferredFillStepNanoseconds)
                }
            }

            self.deferredInitialStatusIDs = []
            self.deferredStatusUpdates = [:]
            self.deferredDeletedStatusIDs = []
            self.persistCurrentStatusesToCache()
            self.deferredInitialFillTask = nil
        }
    }

    fileprivate func persistSingleStatusUpdateToCache(_ status: Status) {
        guard let cacheFilter = timelineCacheFilter else { return }
        Task { [weak self] in
            guard let self else { return }
            await timelineCache.updateStatus(
                status,
                for: cacheClientID,
                filter: cacheFilter
            )
        }
    }

    fileprivate func removeStatusFromCache(id: String) {
        if deferredInitialStatusIDs.contains(id) { deferredDeletedStatusIDs.insert(id) }
        guard let cacheFilter = timelineCacheFilter else { return }
        Task { [weak self] in
            guard let self else { return }
            await timelineCache.removeStatus(
                id: id,
                for: cacheClientID,
                filter: cacheFilter
            )
        }
    }
}
