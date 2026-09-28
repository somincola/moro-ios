//
//  NotificationsViewModel.swift
//  moro
//
//  ViewModel for managing notifications data and state.
//

import Foundation
import Combine

@MainActor
final class NotificationFeedStore: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let apiClient: MastodonAPI
    private let snapshotStore: NotificationSnapshotStore
    private let snapshotSession: NotificationSnapshotStore.Session?
    private let minimumRefreshInterval: TimeInterval
    private var models: [MastodonNotificationScope: NotificationsViewModel] = [:]

    init(apiClient: MastodonAPI, sessionID: String? = nil,
        snapshotStore: NotificationSnapshotStore? = nil, minimumRefreshInterval: TimeInterval = 30) {
        self.apiClient = apiClient
        let snapshotStore = snapshotStore ?? .shared
        self.snapshotStore = snapshotStore
        self.snapshotSession = sessionID.map { snapshotStore.session(for: $0) }
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    func model(for scope: MastodonNotificationScope) -> NotificationsViewModel {
        if let model = models[scope] { return model }
        let model = NotificationsViewModel(apiClient: apiClient, scope: scope,
            snapshotStore: snapshotStore, snapshotSession: snapshotSession,
            minimumRefreshInterval: minimumRefreshInterval) { [weak self] item in
            guard let self else { return }
            for (otherScope, otherModel) in models where otherScope != scope {
                otherModel.removeDisplayItem(item)
            }
        }
        models[scope] = model
        return model
    }
}

struct NotificationFilterInsight: Equatable {
    let fetchedCount: Int
    let visibleCount: Int
    let hiddenByTypeCount: Int
    let hiddenByPolicyCount: Int
    let policy: AppSettings.NotificationPolicy

    static let empty = NotificationFilterInsight(
        fetchedCount: 0,
        visibleCount: 0,
        hiddenByTypeCount: 0,
        hiddenByPolicyCount: 0,
        policy: .anyone
    )

    var hiddenCount: Int {
        hiddenByTypeCount + hiddenByPolicyCount
    }

    var hidesEverything: Bool {
        fetchedCount > 0 && visibleCount == 0 && hiddenCount > 0
    }

    var hidesAnything: Bool {
        hiddenCount > 0
    }
}

@MainActor
final class NotificationsViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}


    enum LoadingState {
        case idle
        case loading
        case refreshing
        case loadingMore
        case loaded
        case error(Error)
    }

    @Published var notifications: [NotificationDisplayItem] = []
    @Published var loadingState: LoadingState = .idle
    /// True when the most recent load-more page failed; drives the inline retry footer.
    @Published var loadMoreFailed: Bool = false
    @Published private(set) var refreshFailed = false
    @Published private(set) var hasMore = true
    @Published private(set) var acceptingFollowRequestIDs: Set<String> = []
    @Published private(set) var rejectingFollowRequestIDs: Set<String> = []
    @Published private(set) var filterInsight: NotificationFilterInsight = .empty

    private let apiClient: MastodonAPI
    let scope: MastodonNotificationScope
    private var activationTask: Task<String?, Never>?
    private var refreshTask: Task<String?, Never>?
    private var currentMaxID: String?
    private var newestNotificationID: String?
    private var rawNotifications: [NotificationItem] = []
    private let prefetchCoordinator: StatusDetailPrefetchCoordinator
    private let detailPerfTracker: StatusDetailPerformanceTracker
    private let onFollowRequestResolved: ((NotificationDisplayItem) -> Void)?
    private let snapshotStore: NotificationSnapshotStore
    private let snapshotSession: NotificationSnapshotStore.Session?
    private let minimumRefreshInterval: TimeInterval
    private var didAttemptSnapshotRestore = false
    private var needsSnapshotRevalidation = false
    private var lastSuccessfulRefresh: Date?
    private var removedNotificationIDs: Set<String> = []

    // Cache for relationships to avoid repeated API calls
    private var relationshipCache: [String: Relationship] = [:]

    init(
        apiClient: MastodonAPI,
        scope: MastodonNotificationScope = .everything,
        prefetchCoordinator: StatusDetailPrefetchCoordinator? = nil,
        detailPerfTracker: StatusDetailPerformanceTracker? = nil,
        snapshotStore: NotificationSnapshotStore? = nil,
        snapshotSession: NotificationSnapshotStore.Session? = nil,
        minimumRefreshInterval: TimeInterval = 30,
        onFollowRequestResolved: ((NotificationDisplayItem) -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.scope = scope
        self.prefetchCoordinator = prefetchCoordinator ?? .shared
        self.detailPerfTracker = detailPerfTracker ?? .shared
        self.onFollowRequestResolved = onFollowRequestResolved
        self.snapshotStore = snapshotStore ?? .shared
        self.snapshotSession = snapshotSession
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    // MARK: - Public Methods

    @discardableResult
    func activate(forceRefresh: Bool = false) async -> String? {
        if let activationTask { return await activationTask.value }
        // The cached feed owns this request, so switching tabs cannot cancel its
        // initial load and leave the next visit waiting on a cancelled view task.
        let task = Task { @MainActor in
            switch self.loadingState {
            case .idle, .error:
                return await self.loadInitial()
            case .loaded:
                if !forceRefresh, !self.refreshFailed,
                    let last = self.lastSuccessfulRefresh,
                    Date().timeIntervalSince(last) < self.minimumRefreshInterval {
                    return nil
                }
                return await self.refresh()
            case .loading, .refreshing, .loadingMore:
                return nil
            }
        }
        activationTask = task
        defer { activationTask = nil }
        return await task.value
    }

    @discardableResult
    func loadInitial() async -> String? {
        guard isCurrentSession else { return nil }
        // Allow retrying from .error (the empty-state retry button calls this); only bail
        // out when a load is already in flight.
        switch loadingState {
        case .idle, .error:
            break
        default:
            return nil
        }

        loadingState = .loading
        refreshFailed = false

        if !didAttemptSnapshotRestore {
            didAttemptSnapshotRestore = true
            if let snapshotSession,
                let snapshot = await snapshotStore.load(for: snapshotSession, scope: scope),
                isCurrentSession {
                rawNotifications = snapshot.notifications
                newestNotificationID = snapshot.newestID
                currentMaxID = snapshot.olderCursor
                hasMore = snapshot.hasMore
                relationshipCache = snapshot.relationships
                needsSnapshotRevalidation = true
                let filtered = await filterNotifications(rawNotifications, fetchMissingRelationships: false)
                guard isCurrentSession else { return nil }
                notifications = NotificationDisplayItem.consolidate(filtered)
                loadingState = .loaded
                // Disk hydration is never a read acknowledgement or a reason to
                // skip this launch's first network refresh, even for an empty snapshot.
                return await performRefresh()
            }
        }
        guard isCurrentSession else { return nil }

        do {
            let items = try await apiClient.fetchNotifications(
                maxID: nil,
                sinceID: nil,
                limit: 30,
                scope: scope
            )
            let filtered = await filterNotifications(items)
            guard isCurrentSession else { return nil }
            rawNotifications = items
            notifications = NotificationDisplayItem.consolidate(filtered)
            currentMaxID = items.last?.id
            newestNotificationID = items.first?.id
            hasMore = items.count >= 30
            lastSuccessfulRefresh = Date()
            await persistSnapshot()
            guard isCurrentSession else { return nil }
            loadingState = .loaded
            return items.first?.id
        } catch {
            loadingState = .error(error)
            return nil
        }
    }

    @discardableResult
    func refresh() async -> String? {
        if let refreshTask { return await refreshTask.value }
        // SwiftUI can cancel a refresh action as its content changes. Keep the
        // cached feed's request alive and let concurrent callers share its result.
        let task = Task {
            if !self.didAttemptSnapshotRestore, case .idle = self.loadingState {
                return await self.loadInitial()
            }
            return await self.performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return await task.value
    }

    private func performRefresh() async -> String? {
        guard isCurrentSession else { return nil }
        // Don't race an in-flight initial load or pagination (which mutate the same state).
        switch loadingState {
        case .loading, .loadingMore, .refreshing:
            return nil
        default:
            break
        }

        loadingState = .refreshing
        refreshFailed = false
        let sinceID = newestNotificationID
        let revalidateSnapshot = needsSnapshotRevalidation
        do {
            // Fetch all new pages up to the previous newest item, without moving
            // the independent cursor used to read older notifications.
            var items: [NotificationItem] = []
            var revalidatedHead: [NotificationItem] = []
            var pageMaxID: String?
            var visitedCursors: Set<String> = []
            repeat {
                let page = try await apiClient.fetchNotifications(
                    maxID: pageMaxID,
                    sinceID: revalidateSnapshot && pageMaxID == nil ? nil : sinceID,
                    limit: 30,
                    scope: scope
                )
                try Task.checkCancellation()
                guard isCurrentSession else { return nil }
                items.append(contentsOf: page)
                if revalidateSnapshot, pageMaxID == nil {
                    revalidatedHead = page
                    // The latest page already covers the saved head. Otherwise
                    // bridge every new page before joining the old history.
                    if let sinceID, page.contains(where: { $0.id == sinceID })
                        || page.last.map({ Self.isNewerID($0.id, than: sinceID) == false }) == true {
                        break
                    }
                }
                guard sinceID != nil, page.count >= 30,
                    let next = page.last?.id, visitedCursors.insert(next).inserted
                else { break }
                pageMaxID = next
            } while true

            var seenIDs: Set<String> = []
            let retained: [NotificationItem]
            if revalidateSnapshot, revalidatedHead.count < 30 {
                // A complete latest page is authoritative, including an empty inbox.
                retained = []
            } else if revalidateSnapshot, let boundary = revalidatedHead.last?.id {
                let overlap = rawNotifications.lastIndex { saved in revalidatedHead.contains { $0.id == saved.id } }
                retained = rawNotifications.enumerated().compactMap { index, saved in
                    if saved.id == boundary { return nil }
                    if let isNewer = Self.isNewerID(saved.id, than: boundary) { return isNewer ? nil : saved }
                    // Preserve opaque IDs unless the response proves their window.
                    return overlap.map { index > $0 ? saved : nil } ?? saved
                }
            } else {
                retained = rawNotifications
            }
            let merged = (items + retained).filter {
                !removedNotificationIDs.contains($0.id) && seenIDs.insert($0.id).inserted
            }
            let filtered = await filterNotifications(merged)
            try Task.checkCancellation()
            guard isCurrentSession else { return nil }
            rawNotifications = merged
            notifications = NotificationDisplayItem.consolidate(filtered)
            if revalidateSnapshot {
                newestNotificationID = items.first?.id
                currentMaxID = merged.last?.id
                hasMore = revalidatedHead.count >= 30
                needsSnapshotRevalidation = false
            } else {
                newestNotificationID = items.first?.id ?? newestNotificationID
            }
            if !revalidateSnapshot, sinceID == nil {
                currentMaxID = items.last?.id
                hasMore = items.count >= 30
            }
            lastSuccessfulRefresh = Date()
            await persistSnapshot()
            guard isCurrentSession else { return nil }
            loadingState = .loaded
            return newestNotificationID
        } catch {
            // Keep the existing list usable and pagination enabled on a transient refresh
            // failure; only show the full error state when there's nothing to display.
            loadingState = notifications.isEmpty ? .error(error) : .loaded
            refreshFailed = true
            return nil
        }
    }

    func loadMore() async {
        guard isCurrentSession, hasMore, case .loaded = loadingState else { return }

        loadingState = .loadingMore
        loadMoreFailed = false

        do {
            let items = try await apiClient.fetchNotifications(
                maxID: currentMaxID,
                sinceID: nil,
                limit: 30,
                scope: scope
            )
            guard isCurrentSession else { return }
            appendRawNotifications(items)
            let filtered = await filterNotifications(rawNotifications)
            guard isCurrentSession else { return }
            notifications = NotificationDisplayItem.consolidate(filtered)
            hasMore = items.count >= 30 && items.last?.id != currentMaxID
            currentMaxID = items.last?.id ?? currentMaxID
            await persistSnapshot()
            guard isCurrentSession else { return }
            loadingState = .loaded
        } catch {
            loadingState = .loaded
            loadMoreFailed = true
        }
    }

    func isAcceptingFollowRequest(id: String) -> Bool {
        acceptingFollowRequestIDs.contains(id)
    }

    func isRejectingFollowRequest(id: String) -> Bool {
        rejectingFollowRequestIDs.contains(id)
    }

    func acceptFollowRequest(_ item: NotificationDisplayItem) async {
        guard item.type == "follow_request",
            let accountID = item.primaryAccount?.id
        else { return }
        guard !acceptingFollowRequestIDs.contains(item.id),
            !rejectingFollowRequestIDs.contains(item.id)
        else { return }

        acceptingFollowRequestIDs.insert(item.id)
        defer { acceptingFollowRequestIDs.remove(item.id) }

        do {
            _ = try await apiClient.authorizeFollowRequest(accountID: accountID)
            removeDisplayItem(item)
            onFollowRequestResolved?(item)
            await persistResolvedRequest(item)
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Notifications.toastAccepted)
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.Notifications.toastAcceptFailed)
        }
    }

    func rejectFollowRequest(_ item: NotificationDisplayItem) async {
        guard item.type == "follow_request",
            let accountID = item.primaryAccount?.id
        else { return }
        guard !acceptingFollowRequestIDs.contains(item.id),
            !rejectingFollowRequestIDs.contains(item.id)
        else { return }

        rejectingFollowRequestIDs.insert(item.id)
        defer { rejectingFollowRequestIDs.remove(item.id) }

        do {
            _ = try await apiClient.rejectFollowRequest(accountID: accountID)
            removeDisplayItem(item)
            onFollowRequestResolved?(item)
            await persistResolvedRequest(item)
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Notifications.toastRejected)
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.Notifications.toastRejectFailed)
        }
    }
    
    // MARK: - Notification Filtering
    
    /// The server owns notification intake policy. The client must not silently
    /// hide already-delivered notifications based on a second local policy.
    private func filterNotifications(_ items: [NotificationItem], fetchMissingRelationships: Bool = true) async -> [NotificationItem] {
        filterInsight = NotificationFilterInsight(
            fetchedCount: items.count,
            visibleCount: items.count,
            hiddenByTypeCount: 0,
            hiddenByPolicyCount: 0,
            policy: .anyone
        )
        return items
    }

    private func appendRawNotifications(_ newItems: [NotificationItem]) {
        guard !newItems.isEmpty else { return }
        var existingIDs = Set(rawNotifications.map(\.id))
        let uniqueItems = newItems.filter {
            !removedNotificationIDs.contains($0.id) && existingIDs.insert($0.id).inserted
        }
        rawNotifications.append(contentsOf: uniqueItems)
    }

    fileprivate func removeDisplayItem(_ item: NotificationDisplayItem) {
        let sourceIDs = Set(item.sourceNotificationIDs)
        removedNotificationIDs.formUnion(sourceIDs)
        rawNotifications.removeAll { sourceIDs.contains($0.id) }
        notifications.removeAll { $0.id == item.id }
        if let accountID = item.primaryAccount?.id {
            relationshipCache.removeValue(forKey: accountID)
        }
    }

    private var isCurrentSession: Bool {
        snapshotSession.map { snapshotStore.isCurrent($0) } ?? true
    }

    private static func isNewerID(_ lhs: String, than rhs: String) -> Bool? {
        guard !lhs.isEmpty, !rhs.isEmpty,
            lhs.utf8.allSatisfy({ (48...57).contains($0) }),
            rhs.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        // Snowflake IDs may exceed signed integer storage; compare decimal strings.
        return lhs.count == rhs.count ? lhs > rhs : lhs.count > rhs.count
    }

    private func persistSnapshot() async {
        guard let snapshotSession else { return }
        let snapshot = NotificationSnapshotStore.Snapshot(
            notifications: rawNotifications, newestID: newestNotificationID,
            olderCursor: currentMaxID, hasMore: hasMore, relationships: relationshipCache,
            savedAt: lastSuccessfulRefresh ?? Date())
        await snapshotStore.save(snapshot, for: snapshotSession, scope: scope)?.value
    }

    private func persistResolvedRequest(_ item: NotificationDisplayItem) async {
        guard let snapshotSession else { return }
        // Include scopes not instantiated during this launch, so an accepted
        // request cannot return when a different filter restores from disk.
        await snapshotStore.removeNotifications(Set(item.sourceNotificationIDs), for: snapshotSession)?.value
    }

    func prefetchStatusAndQuoteIfNeeded(for status: Status) async {
        await prefetchCoordinator.prefetchStatusAndQuoteIfNeeded(
            for: status,
            apiClient: apiClient
        )
    }

    func prefetchStatusDetailIfNeeded(for status: Status) async {
        await prefetchCoordinator.prefetchStatusIfNeeded(
            for: status,
            apiClient: apiClient
        )
    }

    func traceAndWarmStatusDetailOpen(for status: Status, source: String) async {
        let statusID = status.id
        let coordinator = prefetchCoordinator
        let beforeState = coordinator.warmupState(for: statusID)
        let startMillis = nowMillis()
        await coordinator.prefetchStatusIfNeeded(for: status, apiClient: apiClient)
        let afterState = coordinator.warmupState(for: statusID)
        detailPerfTracker.recordWarmup(
            source: source,
            statusID: statusID,
            before: beforeState,
            after: afterState,
            elapsedMillis: nowMillis() - startMillis
        )
    }

    private func nowMillis() -> Double {
        CFAbsoluteTimeGetCurrent() * 1000
    }
}
