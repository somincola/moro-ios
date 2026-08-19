//
//  StatusDetailPrefetchCoordinator.swift
//  moro
//
//  Centralized prefetch coordinator for status detail threads.
//

import Foundation

@MainActor
final class StatusDetailPrefetchCoordinator {
    @MainActor static let shared = StatusDetailPrefetchCoordinator()
    private static let enableDebugLogging = false

    enum WarmupState: String {
        case cacheHit = "cache-hit"
        case prefetched = "prefetched"
        case inFlight = "in-flight"
        case cold = "cold"
    }

    private var prefetchingStatusIDs: Set<String> = []
    private var prefetchedStatusIDs: Set<String> = []
    private var prefetchTasks: [String: Task<ThreadedConversationModel, Error>] = [:]

    @MainActor private init() {}

    @MainActor
    func warmupState(
        for statusID: String,
        threadCache: ThreadCache? = nil
    ) -> WarmupState {
        let threadCache = threadCache ?? CacheManager.shared.threadCache
        if threadCache.isCached(statusID: statusID) { return .cacheHit }
        if prefetchedStatusIDs.contains(statusID) { return .prefetched }
        if prefetchTasks[statusID] != nil || prefetchingStatusIDs.contains(statusID) { return .inFlight }
        return .cold
    }

    @MainActor
    func prefetchStatusAndQuoteIfNeeded(
        for status: Status,
        apiClient: MastodonAPI,
        threadCache: ThreadCache? = nil,
        accountCache: AccountCache? = nil
    ) async {
        let threadCache = threadCache ?? CacheManager.shared.threadCache
        let accountCache = accountCache ?? CacheManager.shared.accountCache
        await prefetchStatusIfNeeded(
            for: status.displayStatus,
            apiClient: apiClient,
            threadCache: threadCache,
            accountCache: accountCache
        )
        if let quotedStatus = status.quote?.displayableStatus {
            await prefetchStatusIfNeeded(
                for: quotedStatus.displayStatus,
                apiClient: apiClient,
                threadCache: threadCache,
                accountCache: accountCache
            )
        }
    }

    @MainActor
    func prefetchStatusIfNeeded(
        for status: Status,
        apiClient: MastodonAPI,
        threadCache: ThreadCache? = nil,
        accountCache: AccountCache? = nil
    ) async {
        let threadCache = threadCache ?? CacheManager.shared.threadCache
        let accountCache = accountCache ?? CacheManager.shared.accountCache
        let statusID = status.id
        let startMillis = nowMillis()

        guard !threadCache.isCached(statusID: statusID) else {
            prefetchedStatusIDs.insert(statusID)
            debugLog("prefetch skipped id=\(statusID) reason=cache-hit")
            return
        }
        guard !prefetchedStatusIDs.contains(statusID) else {
            debugLog("prefetch skipped id=\(statusID) reason=already-prefetched")
            return
        }
        guard prefetchTasks[statusID] == nil, !prefetchingStatusIDs.contains(statusID) else {
            debugLog("prefetch skipped id=\(statusID) reason=in-flight")
            return
        }

        prefetchingStatusIDs.insert(statusID)
        let prefetchTask = Task<ThreadedConversationModel, Error> {
            async let contextTask = apiClient.fetchStatusContext(id: statusID)
            async let detailTask = apiClient.fetchStatusDetail(id: statusID)
            let context = try await contextTask
            let refreshedStatus = try await detailTask
            return ThreadedConversationModel(focusedStatus: refreshedStatus, context: context)
        }
        prefetchTasks[statusID] = prefetchTask
        defer {
            prefetchingStatusIDs.remove(statusID)
            prefetchTasks[statusID] = nil
        }

        do {
            let thread = try await prefetchTask.value
            threadCache.set(thread, for: statusID)
            accountCache.cacheFromThread(thread.threadItems)
            prefetchedStatusIDs.insert(statusID)
            debugLog(
                "prefetch done id=\(statusID) elapsed=\(formatElapsed(nowMillis() - startMillis))")
        } catch {
            // Ignore prefetch errors; detail screen will fall back to normal loading path.
            debugLog(
                "prefetch failed id=\(statusID) elapsed=\(formatElapsed(nowMillis() - startMillis)) error=\(error.localizedDescription)"
            )
        }
    }

    @MainActor
    func awaitInFlightThreadIfNeeded(
        statusID: String,
        threadCache: ThreadCache? = nil,
        accountCache: AccountCache? = nil
    ) async -> ThreadedConversationModel? {
        let threadCache = threadCache ?? CacheManager.shared.threadCache
        let accountCache = accountCache ?? CacheManager.shared.accountCache
        if let cached = threadCache.get(statusID: statusID) {
            return cached
        }
        guard let task = prefetchTasks[statusID] else { return nil }

        let startMillis = nowMillis()
        do {
            let thread = try await task.value
            threadCache.set(thread, for: statusID)
            accountCache.cacheFromThread(thread.threadItems)
            prefetchedStatusIDs.insert(statusID)
            debugLog(
                "detail consumed in-flight prefetch id=\(statusID) wait=\(formatElapsed(nowMillis() - startMillis))"
            )
            return thread
        } catch {
            debugLog("detail failed waiting in-flight prefetch id=\(statusID)")
            return nil
        }
    }

    private func nowMillis() -> Double {
        CFAbsoluteTimeGetCurrent() * 1000
    }

    private func formatElapsed(_ millis: Double) -> String {
        String(format: "%.0fms", millis)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
            AppLogger.performanceLog(
                "⏱️ [DetailPrefetch] \(message)",
                enabled: Self.enableDebugLogging || AppLogger.isPerformanceEnabled
            )
        #endif
    }
}
