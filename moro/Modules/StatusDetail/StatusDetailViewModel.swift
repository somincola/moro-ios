//
//  StatusDetailViewModel.swift
//  moro
//
//  Manages thread data and state for status detail view.
//

import Foundation
import Combine

@MainActor
final class StatusDetailViewModel: ObservableObject, FeedCoordinatorUpdatable {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(Error)
    }

    enum HistoryLoadingState {
        case idle
        case loading
        case loaded
        case error(Error)
    }
    
    /// The focused status (initially provided)
    @Published var focusedStatus: Status
    
    /// The full thread conversation model
    @Published var threadModel: ThreadedConversationModel?
    
    /// Loading state
    @Published var loadingState: LoadingState = .idle
    @Published var statusHistory: [StatusEditHistoryItem] = []
    @Published var historyLoadingState: HistoryLoadingState = .idle
    
    private let apiClient: MastodonAPI
    private let threadCache: ThreadCache
    private let accountCache: AccountCache
    private let feedCoordinator: FeedCoordinator
    private let prefetchCoordinator: StatusDetailPrefetchCoordinator
    private let detailPerfTracker: StatusDetailPerformanceTracker
    private let cacheFreshnessInterval: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var statusUpdateRevision: UInt64 = 0
    private var latestStatusUpdates: [String: (revision: UInt64, status: Status)] = [:]
    
    init(
        status: Status,
        apiClient: MastodonAPI,
        threadCache: ThreadCache? = nil,
        accountCache: AccountCache? = nil,
        feedCoordinator: FeedCoordinator? = nil,
        prefetchCoordinator: StatusDetailPrefetchCoordinator? = nil,
        detailPerfTracker: StatusDetailPerformanceTracker? = nil,
        cacheFreshnessInterval: TimeInterval = 15
    ) {
        self.focusedStatus = status
        self.apiClient = apiClient
        self.feedCoordinator = feedCoordinator ?? .shared
        self.prefetchCoordinator = prefetchCoordinator ?? .shared
        self.detailPerfTracker = detailPerfTracker ?? .shared
        self.cacheFreshnessInterval = cacheFreshnessInterval
        // Use provided caches or fall back to shared instance
        self.threadCache = threadCache ?? CacheManager.shared.threadCache
        self.accountCache = accountCache ?? CacheManager.shared.accountCache
        
        // Listen to feed coordinator updates
        self.feedCoordinator.$mostRecentUpdate
            .compactMap { $0 }
            .sink { [weak self] update in
                self?.incorporateUpdate(update)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    /// Load the thread context (ancestors and descendants)
    func loadThread() async {
        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { await performLoadThread() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoadThread() async {
        let loadStartMillis = nowMillis()
        let statusID = focusedStatus.id
        let initialWarmupState = prefetchCoordinator.warmupState(for: statusID, threadCache: threadCache)

        // Skip if already loading or loaded with correct data
        switch loadingState {
        case .loading:
            return
        case .loaded:
            // Check if we already have the correct thread loaded
            if threadModel?.focusedID == focusedStatus.id {
                return
            }
            // Otherwise, we need to reload for a different status
            loadingState = .idle
        case .idle, .error:
            break
        }
        
        // Check cache first
        let cachedThreadIsFresh = threadCache.isFresh(
            statusID: statusID,
            maximumAge: cacheFreshnessInterval
        )
        if let cachedThread = threadCache.get(statusID: statusID),
           cachedThread.focusedID == statusID {
            presentThread(cachedThread, focusedStatusID: statusID)
            loadingState = .loaded
            detailPerfTracker.recordFirstScreen(
                statusID: statusID,
                path: .cacheHit,
                warmupState: initialWarmupState,
                elapsedMillis: nowMillis() - loadStartMillis
            )

            // Counts and per-account interaction flags are volatile. Keep the
            // cached thread for an immediate first frame, but revalidate an
            // older snapshot instead of showing zeros until the next action.
            if !cachedThreadIsFresh {
                await revalidateCachedThread(statusID: statusID)
            }
            return
        }

        loadingState = .loading

        if let prefetchedThread = await prefetchCoordinator.awaitInFlightThreadIfNeeded(
            statusID: statusID,
            threadCache: threadCache,
            accountCache: accountCache
        ) {
            presentThread(prefetchedThread, focusedStatusID: statusID)
            loadingState = .loaded
            detailPerfTracker.recordFirstScreen(
                statusID: statusID,
                path: .prefetchHit,
                warmupState: initialWarmupState,
                elapsedMillis: nowMillis() - loadStartMillis
            )
            return
        }

        // Reuse coordinator's shared task path for cold opens to avoid duplicated
        // network fetches across warmup and detail loading.
        await prefetchCoordinator.prefetchStatusIfNeeded(
            for: focusedStatus.displayStatus,
            apiClient: apiClient,
            threadCache: threadCache,
            accountCache: accountCache
        )

        if let warmedThread = threadCache.get(statusID: focusedStatus.id),
           warmedThread.focusedID == focusedStatus.id {
            presentThread(warmedThread, focusedStatusID: statusID)
            loadingState = .loaded
            detailPerfTracker.recordFirstScreen(
                statusID: statusID,
                path: .prefetchHit,
                warmupState: initialWarmupState,
                elapsedMillis: nowMillis() - loadStartMillis
            )
            return
        }

        do {
            let thread = try await fetchFreshThread(statusID: statusID)
            storeAndPresentThread(thread, focusedStatusID: statusID)
            
            loadingState = .loaded
            detailPerfTracker.recordFirstScreen(
                statusID: statusID,
                path: .coldOpen,
                warmupState: initialWarmupState,
                elapsedMillis: nowMillis() - loadStartMillis
            )
        } catch {
            loadingState = .error(error)
            detailPerfTracker.recordFirstScreen(
                statusID: statusID,
                path: .failed,
                warmupState: initialWarmupState,
                elapsedMillis: nowMillis() - loadStartMillis
            )
        }
    }

    private func revalidateCachedThread(statusID: String) async {
        do {
            let thread = try await fetchFreshThread(statusID: statusID)
            storeAndPresentThread(thread, focusedStatusID: statusID)
        } catch {
            // Cached content remains usable. A transient refresh failure should
            // not replace an already-rendered conversation with an error state.
        }
    }

    private func fetchFreshThread(statusID: String) async throws -> ThreadedConversationModel {
        let revisionAtStart = statusUpdateRevision

        // The context endpoint contains ancestors/descendants but not the
        // focused status itself, so both requests are required and independent.
        async let contextTask = apiClient.fetchStatusContext(id: statusID)
        async let statusTask = apiClient.fetchStatusDetail(id: statusID)
        let context = try await contextTask
        let refreshedStatus = try await statusTask
        let thread = ThreadedConversationModel(
            focusedStatus: refreshedStatus,
            context: context
        )

        // If the user liked/boosted while revalidation was in flight, retain
        // that newer local/server action result instead of letting an older GET
        // response visually roll the action back.
        guard statusUpdateRevision > revisionAtStart else { return thread }
        var items = thread.threadItems
        let updates = latestStatusUpdates.values
            .filter { $0.revision > revisionAtStart }
            .sorted { $0.revision < $1.revision }
        for update in updates {
            let canonicalUpdate = update.status.displayStatus
            guard let index = items.firstIndex(where: {
                $0.status.id == canonicalUpdate.id
                    || $0.status.displayStatus.id == canonicalUpdate.id
            }) else { continue }
            let item = items[index]
            items[index] = ThreadItem(
                status: item.status.incorporatingDisplayStatusUpdate(canonicalUpdate),
                position: item.position,
                replyDepth: item.replyDepth
            )
        }
        thread.threadItems = items
        return thread
    }

    private func presentThread(_ thread: ThreadedConversationModel, focusedStatusID: String) {
        threadModel = thread
        if let focused = thread.threadItems.first(where: { $0.status.id == focusedStatusID })?.status {
            focusedStatus = focused
        }
        accountCache.cacheFromThread(thread.threadItems)
    }

    private func storeAndPresentThread(
        _ thread: ThreadedConversationModel,
        focusedStatusID: String
    ) {
        threadCache.set(thread, for: focusedStatusID)
        presentThread(thread, focusedStatusID: focusedStatusID)
    }
    
    /// Refresh the thread (force reload, ignoring cache)
    func refresh() async {
        // Invalidate cache for this thread
        threadCache.invalidate(statusID: focusedStatus.id)
        loadingState = .idle
        await loadThread()
    }

    func loadStatusHistory(forceReload: Bool = false) async {
        if !forceReload {
            switch historyLoadingState {
            case .loading:
                return
            case .loaded where !statusHistory.isEmpty:
                return
            default:
                break
            }
        }

        historyLoadingState = .loading
        do {
            let targetID = focusedStatus.displayStatus.id
            let items = try await apiClient.fetchStatusHistory(id: targetID)
            statusHistory = items.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            historyLoadingState = .loaded
        } catch {
            historyLoadingState = .error(error)
        }
    }
    
    // MARK: - Status Updates

    /// Update a status in the thread (for optimistic updates)
    func updateStatus(_ status: Status) {
        var didChange = false

        // Update focused status if it matches
        if focusedStatus.id == status.id || focusedStatus.displayStatus.id == status.id {
            focusedStatus = focusedStatus.incorporatingDisplayStatusUpdate(status)
            didChange = true
        }

        // Update in thread model
        if let model = threadModel {
            if let index = model.threadItems.firstIndex(where: {
                $0.status.id == status.id || $0.status.displayStatus.id == status.id
            }) {
                let mergedStatus = model.threadItems[index].status.incorporatingDisplayStatusUpdate(status)
                let updatedItem = ThreadItem(
                    status: mergedStatus,
                    position: model.threadItems[index].position,
                    replyDepth: model.threadItems[index].replyDepth
                )
                var items = model.threadItems
                items[index] = updatedItem
                model.threadItems = items
                threadModel = model
                didChange = true
            }
        }

        // Only invalidate when this thread actually changed — otherwise every unrelated
        // like/boost from the feed coordinator thrashed the cache of detail views stacked
        // underneath this one.
        guard didChange else { return }
        statusUpdateRevision &+= 1
        latestStatusUpdates[status.displayStatus.id] = (
            revision: statusUpdateRevision,
            status: status
        )
        threadCache.invalidate(statusID: focusedStatus.id)
    }

    func removeStatus(id: String) {
        guard let model = threadModel,
              model.threadItems.contains(where: { $0.status.id == id }) else { return }

        var items = model.threadItems
        items.removeAll { $0.status.id == id }
        model.threadItems = items
        threadModel = model
        threadCache.invalidate(statusID: focusedStatus.id)
    }

    /// Vote on a poll
    func votePoll(pollID: String, choices: [Int]) async -> Bool {
        do {
            let updatedPoll = try await apiClient.votePoll(pollID: pollID, choices: choices)
            // Update whichever thread status actually owns this poll — it may be a reply,
            // not the focused post — and via updating(poll:) so no fields are dropped
            // (the old hand-rebuilt Status silently lost filtered/pinned/editedAt).
            guard let owner = statusOwningPoll(pollID) else { return false }
            updateStatus(owner.updating(poll: updatedPoll))
            return true
        } catch {
            AppLogger.error("Failed to vote on poll: \(error)")
            return false
        }
    }

    private func statusOwningPoll(_ pollID: String) -> Status? {
        let candidates = [focusedStatus] + (threadModel?.threadItems.map(\.status) ?? [])
        return candidates.first { $0.displayStatus.poll?.id == pollID }
    }

    // MARK: - Cache Access
    
    /// Get account info from cache (for reply headers, etc.)
    func getCachedAccount(id: String) -> Account? {
        return accountCache.get(id: id)
    }
    
    // MARK: - FeedCoordinatorUpdatable
    
    func incorporateUpdate(_ update: UpdatedElement) {
        switch update {
        case .createdPost:
            break
        case .post(let updatedStatus):
            updateStatus(updatedStatus)
        case .deletedPost(let deletedID):
            // Only rewrite threadItems when the deleted post is actually in this thread —
            // reassigning the array fires the thread model's objectWillChange even on no
            // match, re-rendering detail views stacked underneath on every unrelated deletion.
            if let model = threadModel,
                model.threadItems.contains(where: { $0.status.id == deletedID }) {
                var items = model.threadItems
                items.removeAll { $0.status.id == deletedID }
                model.threadItems = items
                threadModel = model
            }
            // If focused status was deleted, handle appropriately
            if focusedStatus.id == deletedID {
                // Could show a message or navigate back
            }
        case .hashtag, .relationship:
            // Not applicable for status detail
            break
        }
    }

    private func nowMillis() -> Double {
        CFAbsoluteTimeGetCurrent() * 1000
    }
}
