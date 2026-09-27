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
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

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

    @Published private(set) var newPostCount = 0
    @Published private(set) var newPostsHaveMore = false
    @Published private(set) var liveRevision: UInt64 = 0
    @Published private(set) var presentationRevision: UInt64 = 0
    @Published private(set) var gaps: [TimelineGap] = []
    @Published private(set) var loadingGapIDs: Set<UUID> = []
    @Published private(set) var failedGapIDs: Set<UUID> = []
    private var liveTimeline: TimelineLiveUpdates?
    private var liveVersion: UInt64 = 0
    private var appliedLiveVersion: UInt64 = 0
    private(set) var presentedSequence: UInt64 = 0
    private var publishLiveTask: Task<Void, Never>?
    private var automaticGapTask: Task<Void, Never>?
    private var automaticGapBudget = 0
    private var gapTask: (id: UUID, task: Task<Bool, Never>)?
    private var gapRequests: [UUID: Task<Bool, Never>] = [:]
    // Publish failures with the body snapshot so retry rows use the same
    // anchor-preserving transaction when they appear or disappear.
    private var failedGapRequestIDs: Set<UUID> = []
    private var dataGeneration = UUID()
    private var cacheWriteTask: Task<Void, Never>?
    private(set) var lastLatestCheckAt: Date?
    private var anonymousPendingIDs: Set<String> = []
    private let defersLivePresentation: Bool
    var currentAccountID: String?

    var hasUnappliedUpdates: Bool { liveVersion != appliedLiveVersion }
    var detectionBaselineID: String? { liveTimeline?.metadata.fetchedHeadID ?? currentSinceID }
    var hasReadingState: Bool { liveTimeline != nil }
    var canonicalStatusIDs: Set<String> { Set((liveTimeline?.statuses ?? statuses).map(\.id)) }
    var savedReadingAnchor: TimelineReadingAnchor? { liveTimeline?.metadata.readingAnchor }

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
        bootstrapConfig: BootstrapConfig = .adaptiveDefault(),
        defersLivePresentation: Bool = false
    ) {
        self.apiClient = apiClient
        self.timelineType = timelineType
        self.feedCoordinator = feedCoordinator ?? .shared
        self.timelineCache = timelineCache ?? CacheManager.shared.timelineCache
        self.cacheClientID = cacheClientID
        self.bootstrapConfig = bootstrapConfig
        self.defersLivePresentation = defersLivePresentation
        // Use provided cache or fall back to shared instance
        self.accountCache = accountCache ?? CacheManager.shared.accountCache

        // Listen to feed coordinator updates
        self.feedCoordinator.updates
            .sink { [weak self] update in
                self?.incorporateUpdate(update)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .timelineContentWillClear)
            .sink { [weak self] notification in
                guard let self, notification.object as? TimelineCache === self.timelineCache else { return }
                self.clearStatuses()
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

        let generation = dataGeneration
        deferredInitialFillTask?.cancel()
        initialLoadState = .loading
        let hydrationTask = Task { [weak self] in
            guard let self else { return false }
            return await self.hydrateFromCacheIfAvailable()
        }
        let hydratedFromCache = await awaitCacheHydrationResult(from: hydrationTask)
        let cachedStatusesBeforeNetwork = await loadCachedStatusesSnapshot()
        guard generation == dataGeneration, !Task.isCancelled else { return }

        do {
            let page = try await apiClient.fetchTimelinePage(timeline: timelineType,
                maxID: nil, sinceID: nil, limit: bootstrapConfig.initialLoadLimit)
            let newStatuses = page.statuses

            let cachedStatusesForMerge: [Status]
            if hydratedFromCache, !cachedStatusesBeforeNetwork.isEmpty {
                cachedStatusesForMerge = cachedStatusesBeforeNetwork
            } else {
                cachedStatusesForMerge = await loadCachedStatusesSnapshot()
            }
            guard generation == dataGeneration, !Task.isCancelled else { return }
            var initialLive: TimelineLiveUpdates
            if cachedStatusesForMerge.isEmpty {
                initialLive = TimelineLiveUpdates(statuses: newStatuses,
                    metadata: page.isPartial ? TimelineLiveMetadata() : nil)
            } else {
                let cachedState = await timelineCache.getLiveMetadata(for: cacheClientID, filter: timelineCacheFilter!)
                guard generation == dataGeneration, !Task.isCancelled else { return }
                initialLive = liveTimeline ?? TimelineLiveUpdates(statuses: cachedStatusesForMerge, metadata: cachedState)
                _ = initialLive.receiveHead(page,
                    sinceID: initialLive.metadata.fetchedHeadID, currentAccountID: currentAccountID)
            }
            if let earlyUpdates = liveTimeline {
                let knownIDs = Set(initialLive.statuses.map(\.id))
                for status in earlyUpdates.statuses.reversed() where !knownIDs.contains(status.id) {
                    initialLive.receive(status, currentAccountID: currentAccountID)
                }
            }
            liveTimeline = initialLive
            if !initialLive.metadata.gaps.isEmpty { automaticGapBudget = 2 }
            let mergedStatuses = initialLive.statuses
            let anchorIndex = initialLive.metadata.readingAnchor.flatMap { anchor in
                mergedStatuses.firstIndex { $0.id == anchor.statusID }
            }
            let renderCount = max(bootstrapConfig.initialRenderCap, anchorIndex.map { $0 + 4 } ?? 0)
            let initialStatuses = Array(mergedStatuses.prefix(renderCount))
            let deferredStatuses = Array(
                mergedStatuses.dropFirst(initialStatuses.count)
            )
            deferredInitialFillTask?.cancel()
            let preservesCachedPresentation = defersLivePresentation && !statuses.isEmpty
            if !preservesCachedPresentation {
                statuses = initialStatuses
                currentMaxID = initialStatuses.last?.id
                gaps = initialLive.metadata.gaps
                presentedSequence = initialLive.metadata.sequence
                appliedLiveVersion = liveVersion
                presentationRevision &+= 1
            }
            currentSinceID = initialLive.metadata.fetchedHeadID
            initialLoadState = .loaded
            if preservesCachedPresentation { liveContentChanged(immediate: true) }
            else { publishLiveNotice() }
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
                await timelineCache.setLiveSnapshot(statuses: mergedStatuses, live: initialLive.metadata,
                    for: cacheClientID, filter: filter)
            }
            if !deferredStatuses.isEmpty {
                scheduleDeferredInitialFill(with: deferredStatuses)
            } else {
                deferredInitialFillTask = nil
            }
        } catch {
            guard generation == dataGeneration, !Task.isCancelled else { return }
            // Keep cached timeline usable when first network backfill fails.
            let cachedFallbackStatuses: [Status]
            if hydratedFromCache, !cachedStatusesBeforeNetwork.isEmpty {
                cachedFallbackStatuses = cachedStatusesBeforeNetwork
            } else {
                cachedFallbackStatuses = await loadCachedStatusesSnapshot()
            }

            if !cachedFallbackStatuses.isEmpty {
                deferredInitialFillTask?.cancel()
                let cachedState = await timelineCache.getLiveMetadata(for: cacheClientID, filter: timelineCacheFilter!)
                guard generation == dataGeneration, !Task.isCancelled else { return }
                liveTimeline = TimelineLiveUpdates(statuses: cachedFallbackStatuses, metadata: cachedState)
                let anchorIndex = cachedState?.readingAnchor.flatMap { anchor in
                    cachedFallbackStatuses.firstIndex { $0.id == anchor.statusID }
                }
                statuses = Array(cachedFallbackStatuses.prefix(max(bootstrapConfig.initialRenderCap, anchorIndex.map { $0 + 4 } ?? 0)))
                gaps = liveTimeline?.metadata.gaps ?? []
                presentedSequence = liveTimeline?.metadata.sequence ?? 0
                presentationRevision &+= 1
                publishLiveNotice()
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

    @discardableResult
    func refresh(trigger: RefreshTrigger = .pull) async -> RefreshResult {
        if let activeRefreshRequest { return await activeRefreshRequest.task.value }
        let requestID = UUID()
        let generation = dataGeneration
        let task = Task { [weak self] in
            guard let self else { return RefreshResult.cancelled }
            return await self.performRefresh(trigger: trigger, generation: generation)
        }
        activeRefreshRequest = (requestID, task)
        let result = await task.value
        if activeRefreshRequest?.id == requestID { activeRefreshRequest = nil }
        return result
    }

    private func performRefresh(trigger: RefreshTrigger, generation: UUID) async -> RefreshResult {
        refreshState = .refreshing(trigger)
        lastLatestCheckAt = Date()
        ensureLiveTimeline()
        let baseline = detectionBaselineID
        do {
            let page = try await apiClient.fetchTimelinePage(
                timeline: timelineType, maxID: nil, sinceID: baseline,
                limit: bootstrapConfig.refreshLoadLimit)
            try Task.checkCancellation()
            guard generation == dataGeneration else { return .cancelled }
            let count = receiveDetectedPage(page, sinceID: baseline)
            initialLoadState = .loaded
            refreshState = .idle
            triggeredLoadMoreForStatusIDs.removeAll()
            if currentMaxID == nil { currentMaxID = page.statuses.last?.id }
            return .success(insertedCount: count, replacedTimeline: false)
        } catch is CancellationError {
            if generation == dataGeneration { refreshState = .idle }
            return .cancelled
        } catch {
            guard generation == dataGeneration else { return .cancelled }
            refreshState = .failed(error)
            if statuses.isEmpty { initialLoadState = .failed(error) }
            return .failure(error)
        }
    }

    private func ensureLiveTimeline() {
        if liveTimeline == nil { liveTimeline = TimelineLiveUpdates(statuses: statuses) }
    }

    func receiveLiveStatus(_ status: Status, authoredByCurrentUser: Bool = false) {
        ensureLiveTimeline()
        liveTimeline?.receive(status,
            currentAccountID: authoredByCurrentUser ? status.account.id : currentAccountID)
        liveTimeline?.trimUnapplied(presentedIDs: Set(statuses.map(\.id)))
        liveContentChanged(immediate: false)
    }

    @discardableResult
    func receiveDetectedPage(_ page: TimelinePage, sinceID: String?) -> Int {
        ensureLiveTimeline()
        let previousGapIDs = Set(liveTimeline?.metadata.gaps.map(\.id) ?? [])
        let inserted = liveTimeline?.receiveHead(page, sinceID: sinceID, currentAccountID: currentAccountID) ?? 0
        liveTimeline?.trimUnapplied(presentedIDs: Set(statuses.map(\.id)))
        currentSinceID = liveTimeline?.metadata.fetchedHeadID
        // REST may only confirm posts already delivered by the stream. Its
        // unverified interval still needs a quiet probe, even with no new rows.
        if inserted > 0 || liveTimeline?.metadata.gaps.contains(where: { !previousGapIDs.contains($0.id) }) == true {
            automaticGapBudget = 2
        }
        accountCache.cacheFromStatuses(page.statuses)
        liveContentChanged(immediate: true)
        return inserted
    }

    private func liveContentChanged(immediate: Bool) {
        liveVersion &+= 1
        if !defersLivePresentation {
            applyLiveUpdates()
            return
        }
        if immediate {
            publishLiveTask?.cancel()
            publishLiveTask = nil
            publishLiveNotice()
        } else if publishLiveTask == nil {
            // Fixed deadline: a busy stream cannot keep postponing the flush.
            publishLiveTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self else { return }
                self.publishLiveTask = nil
                self.publishLiveNotice()
            }
        }
    }

    private func publishLiveNotice() {
        guard let liveTimeline else { return }
        anonymousPendingIDs.subtract(liveTimeline.statuses.map(\.id))
        let nextIDs = Set(liveTimeline.metadata.newIDs.keys).union(anonymousPendingIDs)
        if pendingNewStatusIDs != nextIDs { pendingNewStatusIDs = nextIDs }
        if newPostCount != nextIDs.count { newPostCount = nextIDs.count }
        if newPostsHaveMore != liveTimeline.hasMoreNew { newPostsHaveMore = liveTimeline.hasMoreNew }
        if liveRevision != liveVersion { liveRevision = liveVersion }
    }

    /// Called by the owning page after capturing a reading anchor, never by a
    /// network callback while that page is being dragged or restored.
    @discardableResult
    func applyLiveUpdates() -> Bool {
        guard hasUnappliedUpdates, let liveTimeline else { return false }
        publishLiveTask?.cancel()
        publishLiveTask = nil
        statuses = liveTimeline.statuses
        currentMaxID = statuses.last?.id
        gaps = liveTimeline.metadata.gaps
        failedGapRequestIDs.formIntersection(gaps.map(\.id))
        failedGapIDs = failedGapRequestIDs
        presentedSequence = liveTimeline.metadata.sequence
        appliedLiveVersion = liveVersion
        presentationRevision &+= 1
        publishLiveNotice()
        persistCurrentStatusesToCache()
        return true
    }

    func acknowledgePresentedUpdates(through sequence: UInt64) {
        guard sequence <= presentedSequence, let state = liveTimeline,
            sequence > state.metadata.acknowledgedSequence else { return }
        let acknowledgedIDs = liveTimeline!.metadata.newIDs.filter { $0.value <= sequence }.map(\.key)
        liveTimeline?.acknowledge(through: sequence)
        pendingNewStatusIDs.subtract(acknowledgedIDs)
        publishLiveNotice()
        persistCurrentStatusesToCache()
    }

    func saveReadingAnchor(_ anchor: TimelineReadingAnchor?) {
        guard liveTimeline?.metadata.readingAnchor != anchor else { return }
        ensureLiveTimeline()
        liveTimeline?.setReadingAnchor(anchor)
        persistCurrentStatusesToCache()
    }

    func fillRecentGapsIfNeeded(near visibleStatusIDs: Set<String> = []) {
        guard automaticGapTask == nil,
            nextAutomaticGap(near: visibleStatusIDs) != nil else { return }
        let generation = dataGeneration
        automaticGapTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == self.dataGeneration { self.automaticGapTask = nil }
            }
            // Bound each batch. The next settled layout supplies fresh visible
            // anchors before another batch, so older gaps load as they approach.
            for _ in 0..<2 {
                guard !Task.isCancelled, generation == self.dataGeneration,
                    let gap = self.nextAutomaticGap(near: visibleStatusIDs) else { break }
                self.automaticGapBudget = max(0, self.automaticGapBudget - 1)
                guard await self.loadGap(id: gap.id) else { break }
            }
        }
    }

    private func nextAutomaticGap(near visibleStatusIDs: Set<String>) -> TimelineGap? {
        let candidates = liveTimeline?.metadata.gaps.filter { !failedGapRequestIDs.contains($0.id) } ?? []
        return candidates.first { visibleStatusIDs.contains($0.afterID) || visibleStatusIDs.contains($0.beforeID) }
            ?? (automaticGapBudget > 0 ? candidates.last : nil)
    }

    @discardableResult
    func loadGap(id: UUID) async -> Bool {
        if let request = gapRequests[id] {
            return await request.value
        }
        guard liveTimeline?.metadata.gaps.contains(where: { $0.id == id }) == true else { return false }
        let generation = dataGeneration
        let previousGap = gapTask?.task
        let previousPagination = activeLoadMoreRequest?.task
        loadingGapIDs.insert(id)
        let task = Task { [weak self] in
            guard let self else { return false }
            defer { if generation == self.dataGeneration { self.loadingGapIDs.remove(id) } }
            // Capture predecessors before registering this request. This orders
            // gap and older-page loads without dropping taps or creating cycles.
            if let previousGap { _ = await previousGap.value }
            if let previousPagination { await previousPagination.value }
            guard !Task.isCancelled, generation == self.dataGeneration,
                let gap = self.liveTimeline?.metadata.gaps.first(where: { $0.id == id }) else { return false }
            do {
                let page = try await self.apiClient.fetchTimelinePage(
                    timeline: self.timelineType, maxID: gap.maxID, sinceID: gap.sinceID,
                    limit: self.bootstrapConfig.refreshLoadLimit)
                try Task.checkCancellation()
                guard generation == self.dataGeneration else { return false }
                let progressed = self.liveTimeline?.fillGap(id, page: page, currentAccountID: self.currentAccountID) ?? false
                if progressed { self.failedGapRequestIDs.remove(id) }
                else { self.failedGapRequestIDs.insert(id) }
                self.liveContentChanged(immediate: true)
                return progressed
            } catch {
                guard generation == self.dataGeneration else { return false }
                if !Task.isCancelled {
                    self.failedGapRequestIDs.insert(id)
                    self.liveContentChanged(immediate: true)
                }
                return false
            }
        }
        gapTask = (id, task)
        gapRequests[id] = task
        let result = await task.value
        if generation == dataGeneration {
            gapRequests[id] = nil
            if gapTask?.id == id { gapTask = nil }
        }
        return result
    }

    func loadMore(triggeredByStatusID: String? = nil) async {
        if let activeLoadMoreRequest {
            await activeLoadMoreRequest.task.value
            return
        }

        guard hasMore, currentMaxID != nil else { return }
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
        let generation = dataGeneration
        let previousGap = gapTask?.task
        paginationState = .loading
        let task = Task { [weak self] in
            guard let self else { return }
            if let previousGap { _ = await previousGap.value }
            guard !Task.isCancelled, generation == self.dataGeneration,
                let maxID = self.currentMaxID else { return }
            await self.performLoadMore(maxID: maxID, triggeredByStatusID: triggeredByStatusID)
        }
        activeLoadMoreRequest = (requestID, task)
        await task.value
        if activeLoadMoreRequest?.id == requestID {
            activeLoadMoreRequest = nil
        }
    }

    private func performLoadMore(maxID: String, triggeredByStatusID: String?) async {
        let generation = dataGeneration
        paginationState = .loading

        do {
            let page = try await apiClient.fetchTimelinePage(timeline: timelineType,
                maxID: maxID, sinceID: nil, limit: bootstrapConfig.paginationLoadLimit)
            let newStatuses = page.statuses
            try Task.checkCancellation()
            guard generation == dataGeneration else { return }

            let existingIDs = Set(statuses.map { $0.id })
            let uniqueNewStatuses = newStatuses.filter { !existingIDs.contains($0.id) }
            if !newStatuses.isEmpty {
                let next = page.nextMaxID ?? newStatuses.last?.id
                guard next != maxID else {
                    paginationState = .failed(URLError(.cannotParseResponse))
                    return
                }
                currentMaxID = next
                hasMore = page.isPartial || page.nextMaxID != nil || newStatuses.count >= bootstrapConfig.paginationLoadLimit
                triggeredLoadMoreForStatusIDs.removeAll()

                if !uniqueNewStatuses.isEmpty {
                    if liveTimeline != nil {
                        liveTimeline?.appendOlder(uniqueNewStatuses)
                        liveContentChanged(immediate: true)
                    } else {
                        statuses.append(contentsOf: uniqueNewStatuses)
                        appendStatusesToCache(uniqueNewStatuses)
                    }
                    accountCache.cacheFromStatuses(uniqueNewStatuses)
                }
            } else {
                hasMore = page.isPartial
            }
            paginationState = hasMore ? .idle : .exhausted
        } catch is CancellationError {
            guard generation == dataGeneration else { return }
            paginationState = .idle
            if let statusID = triggeredByStatusID {
                triggeredLoadMoreForStatusIDs.remove(statusID)
            }
        } catch {
            guard generation == dataGeneration else { return }
            paginationState = .failed(error)
            if let statusID = triggeredByStatusID {
                triggeredLoadMoreForStatusIDs.remove(statusID)
            }
        }
    }

    func updateStatus(_ status: Status) {
        if deferredInitialStatusIDs.contains(status.id) {
            deferredStatusUpdates[status.id] = status
        }
        guard (liveTimeline?.statuses ?? statuses).contains(where: {
            $0.id == status.id || $0.displayStatus.id == status.id
        }) else { return }
        ensureLiveTimeline()
        liveTimeline?.update(status)
        liveContentChanged(immediate: true)
    }

    func insertCreatedStatus(_ status: Status) {
        guard timelineType == .home else { return }
        receiveLiveStatus(status, authoredByCurrentUser: true)
        applyLiveUpdates()
        if currentMaxID == nil { currentMaxID = status.id }
        initialLoadState = .loaded
    }

    func stageCreatedStatus(_ status: Status) {
        guard timelineType == .home else { return }
        receiveLiveStatus(status, authoredByCurrentUser: true)
    }

    func removeStatus(id: String) {
        ensureLiveTimeline()
        let removedIDs = liveTimeline!.statuses.filter { $0.id == id || $0.displayStatus.id == id }.map(\.id)
        liveTimeline?.remove(id)
        pendingNewStatusIDs.subtract(removedIDs)
        pendingNewStatusIDs.remove(id)
        if deferredInitialStatusIDs.contains(id) { deferredDeletedStatusIDs.insert(id) }
        if !removedIDs.isEmpty { liveContentChanged(immediate: true) }
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
        automaticGapTask?.cancel()
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
        dataGeneration = UUID()
        cacheWriteTask?.cancel()
        cacheWriteTask = nil
        markerSaveTask?.cancel()
        anonymousPendingIDs = []
        lastLatestCheckAt = nil
        publishLiveTask?.cancel()
        publishLiveTask = nil
        automaticGapTask?.cancel()
        automaticGapTask = nil
        automaticGapBudget = 0
        gapRequests.values.forEach { $0.cancel() }
        gapRequests = [:]
        gapTask = nil
        failedGapRequestIDs = []
        liveTimeline = nil
        liveVersion = 0
        appliedLiveVersion = 0
        presentedSequence = 0
        gaps = []
        loadingGapIDs = []
        failedGapIDs = []
        pendingNewStatusIDs = []
        newPostCount = 0
        newPostsHaveMore = false
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
            removeStatus(id: deletedID)
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
        anonymousPendingIDs.insert(id)
        newPostCount = pendingNewStatusIDs.count

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

        // Presentation, not network success, acknowledges this batch.

        if providesFeedback {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        return true
    }

    /// Clear pending statuses without inserting (e.g., when switching timelines or refreshing)
    func clearPendingStatuses() {
        pendingNewStatusIDs.removeAll()
        anonymousPendingIDs.removeAll()
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
        let generation = dataGeneration
        guard !Task.isCancelled else { return false }
        guard statuses.isEmpty else { return false }
        guard let cacheFilter = timelineCacheFilter else { return false }
        guard
            let cached = await timelineCache.getStatuses(
                for: cacheClientID,
                filter: cacheFilter
            ), !cached.isEmpty
        else { return false }
        guard generation == dataGeneration, !Task.isCancelled else { return false }

        let metadata = await timelineCache.getLiveMetadata(for: cacheClientID, filter: cacheFilter)
        guard generation == dataGeneration, !Task.isCancelled else { return false }
        liveTimeline = TimelineLiveUpdates(statuses: cached, metadata: metadata)
        let anchorIndex = metadata?.readingAnchor.flatMap { anchor in cached.firstIndex { $0.id == anchor.statusID } }
        let renderCount = max(bootstrapConfig.initialRenderCap, anchorIndex.map { $0 + 4 } ?? 0)
        let initialCached = Array(cached.prefix(renderCount))
        let deferredCached = Array(cached.dropFirst(renderCount))

        statuses = initialCached
        gaps = liveTimeline?.metadata.gaps ?? []
        presentedSequence = liveTimeline?.metadata.sequence ?? 0
        presentationRevision &+= 1
        publishLiveNotice()
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
        if let liveTimeline {
            let snapshot = liveTimeline
            let client = cacheClientID
            let cache = timelineCache
            let previous = cacheWriteTask
            let generation = dataGeneration
            cacheWriteTask = Task { [weak self] in
                await previous?.value
                guard !Task.isCancelled, self?.dataGeneration == generation else { return }
                await cache.setLiveSnapshot(statuses: snapshot.statuses, live: snapshot.metadata,
                    for: client, filter: snapshotFilter)
            }
            return
        }
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

    func flushCacheWrites() async {
        persistCurrentStatusesToCache()
        await cacheWriteTask?.value
        await timelineCache.flushPendingWrites()
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
                if !chunk.isEmpty {
                    self.statuses.append(contentsOf: chunk)
                    self.currentMaxID = self.statuses.last?.id
                    self.accountCache.cacheFromStatuses(chunk)
                }
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
