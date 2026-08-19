//
//  NotificationsViewModel.swift
//  moro
//
//  ViewModel for managing notifications data and state.
//

import Foundation
import Combine

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

    enum LoadingState {
        case idle
        case loading
        case loadingMore
        case loaded
        case error(Error)
    }

    @Published var notifications: [NotificationDisplayItem] = []
    @Published var loadingState: LoadingState = .idle
    /// True when the most recent load-more page failed; drives the inline retry footer.
    @Published var loadMoreFailed: Bool = false
    @Published private(set) var acceptingFollowRequestIDs: Set<String> = []
    @Published private(set) var rejectingFollowRequestIDs: Set<String> = []
    @Published private(set) var filterInsight: NotificationFilterInsight = .empty

    private let apiClient: MastodonAPI
    private var currentMaxID: String?
    private var hasMore = true
    private let settings = AppSettings.shared
    private var rawNotifications: [NotificationItem] = []
    private let prefetchCoordinator: StatusDetailPrefetchCoordinator
    private let detailPerfTracker: StatusDetailPerformanceTracker

    // Cache for relationships to avoid repeated API calls
    private var relationshipCache: [String: Relationship] = [:]

    init(
        apiClient: MastodonAPI,
        prefetchCoordinator: StatusDetailPrefetchCoordinator? = nil,
        detailPerfTracker: StatusDetailPerformanceTracker? = nil
    ) {
        self.apiClient = apiClient
        self.prefetchCoordinator = prefetchCoordinator ?? .shared
        self.detailPerfTracker = detailPerfTracker ?? .shared
    }

    // MARK: - Public Methods

    @discardableResult
    func loadInitial() async -> String? {
        // Allow retrying from .error (the empty-state retry button calls this); only bail
        // out when a load is already in flight.
        switch loadingState {
        case .idle, .error:
            break
        default:
            return nil
        }

        loadingState = .loading

        do {
            let items = try await apiClient.fetchNotifications(maxID: nil, sinceID: nil, limit: 30)
            let filtered = await filterNotifications(items)
            rawNotifications = filtered
            notifications = NotificationDisplayItem.consolidate(rawNotifications)
            currentMaxID = items.last?.id
            hasMore = items.count >= 30
            loadingState = .loaded
            return items.first?.id
        } catch {
            loadingState = .error(error)
            return nil
        }
    }

    @discardableResult
    func refresh() async -> String? {
        // Don't race an in-flight initial load or pagination (which mutate the same state).
        switch loadingState {
        case .loading, .loadingMore:
            return nil
        default:
            break
        }

        do {
            let items = try await apiClient.fetchNotifications(maxID: nil, sinceID: nil, limit: 30)
            let filtered = await filterNotifications(items)
            rawNotifications = filtered
            notifications = NotificationDisplayItem.consolidate(rawNotifications)
            currentMaxID = items.last?.id
            hasMore = items.count >= 30
            loadingState = .loaded
            return items.first?.id
        } catch {
            // Keep the existing list usable and pagination enabled on a transient refresh
            // failure; only show the full error state when there's nothing to display.
            loadingState = notifications.isEmpty ? .error(error) : .loaded
            return nil
        }
    }

    func loadMore() async {
        guard hasMore, case .loaded = loadingState else { return }

        loadingState = .loadingMore
        loadMoreFailed = false

        do {
            let items = try await apiClient.fetchNotifications(maxID: currentMaxID, sinceID: nil, limit: 30)
            let filtered = await filterNotifications(items)
            appendRawNotifications(filtered)
            notifications = NotificationDisplayItem.consolidate(rawNotifications)
            currentMaxID = items.last?.id
            hasMore = items.count >= 30
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
            relationshipCache.removeValue(forKey: accountID)
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
            relationshipCache.removeValue(forKey: accountID)
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Notifications.toastRejected)
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.Notifications.toastRejectFailed)
        }
    }
    
    // MARK: - Notification Filtering
    
    /// Filter notifications based on AppSettings
    private func filterNotifications(_ items: [NotificationItem]) async -> [NotificationItem] {
        let fetchedCount = items.count

        // First, filter by notification type
        let typeFiltered = items.filter { notification in
            switch notification.type {
            case "mention":
                return settings.receiveMentionsAndReplies
            case "reblog":
                return settings.receiveBoosts
            case "favourite":
                return settings.receiveFavourites
            case "follow", "follow_request":
                return settings.receiveNewFollowers
            default:
                // Allow other notification types (poll, status, etc.)
                return true
            }
        }
        let hiddenByTypeCount = fetchedCount - typeFiltered.count
        
        // If policy is "anyone", no need to check relationships
        guard settings.notificationPolicy != .anyone else {
            filterInsight = NotificationFilterInsight(
                fetchedCount: fetchedCount,
                visibleCount: typeFiltered.count,
                hiddenByTypeCount: hiddenByTypeCount,
                hiddenByPolicyCount: 0,
                policy: settings.notificationPolicy
            )
            return typeFiltered
        }
        
        // Get unique account IDs that we need relationship info for
        let accountIDs = Set(typeFiltered.map { $0.account.id })
        let accountIDsToFetch = accountIDs.filter { relationshipCache[$0] == nil }
        
        // Fetch relationships for accounts we don't have cached
        if !accountIDsToFetch.isEmpty {
            do {
                let relationships = try await apiClient.fetchRelationships(accountIDs: Array(accountIDsToFetch))
                for relationship in relationships {
                    relationshipCache[relationship.id] = relationship
                }
            } catch {
                // If relationship fetch fails, allow all notifications (fail open)
                AppLogger.error("Failed to fetch relationships: \(error)")
                filterInsight = NotificationFilterInsight(
                    fetchedCount: fetchedCount,
                    visibleCount: typeFiltered.count,
                    hiddenByTypeCount: hiddenByTypeCount,
                    hiddenByPolicyCount: 0,
                    policy: settings.notificationPolicy
                )
                return typeFiltered
            }
        }
        
        // Filter by notification policy
        let policyFiltered = typeFiltered.filter { notification in
            guard let relationship = relationshipCache[notification.account.id] else {
                // If we don't have relationship info, allow the notification (fail open)
                return true
            }
            
            switch settings.notificationPolicy {
            case .anyone:
                return true
            case .followers:
                // Only from accounts that follow me
                return relationship.followedBy
            case .followed:
                // Only from accounts I follow
                return relationship.following
            case .noone:
                return false
            }
        }

        filterInsight = NotificationFilterInsight(
            fetchedCount: fetchedCount,
            visibleCount: policyFiltered.count,
            hiddenByTypeCount: hiddenByTypeCount,
            hiddenByPolicyCount: typeFiltered.count - policyFiltered.count,
            policy: settings.notificationPolicy
        )

        return policyFiltered
    }

    private func appendRawNotifications(_ newItems: [NotificationItem]) {
        guard !newItems.isEmpty else { return }
        let existingIDs = Set(rawNotifications.map(\.id))
        let uniqueItems = newItems.filter { !existingIDs.contains($0.id) }
        rawNotifications.append(contentsOf: uniqueItems)
    }

    private func removeDisplayItem(_ item: NotificationDisplayItem) {
        let sourceIDs = Set(item.sourceNotificationIDs)
        rawNotifications.removeAll { sourceIDs.contains($0.id) }
        notifications = NotificationDisplayItem.consolidate(rawNotifications)
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
