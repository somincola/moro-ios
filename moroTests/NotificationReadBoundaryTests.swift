import Combine
import Foundation
import Testing
@testable import moro

/// The read marker follows what the reader has seen, not what has been downloaded.
@Suite(.serialized) @MainActor
struct NotificationReadBoundaryTests {
    private let numericNewer: @MainActor (String, String) -> Bool? = { lhs, rhs in
        lhs.count == rhs.count ? lhs > rhs : lhs.count > rhs.count
    }

    private func makeStore(api: MockMastodonAPI, unread: Int) async throws -> NotificationUnreadStore {
        let defaults = try #require(UserDefaults(suiteName: "NotificationReadBoundaryTests.\(UUID().uuidString)"))
        api.fetchUnreadNotificationCountHandler = { unread }
        let store = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(),
            badgeSetter: { _ in }
        )
        await store.activate(sessionID: "session", availableSessionIDs: ["session"], apiClient: api)
        return store
    }

    private func item(_ id: Int, groupKey: String? = nil) -> NotificationItem {
        NotificationItem(id: String(id), type: "favourite", createdAt: Date(timeIntervalSince1970: TimeInterval(id)),
            account: ThreadReadingFixtures.status(String(id)).account, status: nil)
    }

    @Test func seenRowLeavesNewerNotificationsUnreadAndTheMarkerNeverMovesBack() async throws {
        let api = MockMastodonAPI()
        var saved: [String] = []
        api.saveMarkerHandler = { _, notifications in
            saved.append(notifications ?? "")
            return Marker()
        }
        let store = try await makeStore(api: api, unread: 5)
        #expect(store.activeUnreadCount == 5)

        // The reader sees notification 8; the two loaded above it are still unread.
        await store.markActiveNotificationsSeen(through: "8", remainingUnread: 2, isNewer: numericNewer)
        #expect(saved == ["8"])
        #expect(store.activeUnreadCount == 2)

        // Scrolling down to older rows never moves the marker back.
        await store.markActiveNotificationsSeen(through: "6", remainingUnread: 4, isNewer: numericNewer)
        await store.markActiveNotificationsSeen(through: "8", remainingUnread: 2, isNewer: numericNewer)
        #expect(saved == ["8"])
        #expect(store.activeUnreadCount == 2)

        await store.markActiveNotificationsSeen(through: "10", remainingUnread: 0, isNewer: numericNewer)
        #expect(saved == ["8", "10"])
        #expect(store.activeUnreadCount == 0)
    }

    @Test func rowsSeenWhileAWriteRunsCollapseIntoOneFollowUpForTheNewest() async throws {
        let api = MockMastodonAPI()
        var saved: [String] = []
        var releaseFirstWrite: CheckedContinuation<Void, Never>?
        api.saveMarkerHandler = { _, notifications in
            if saved.isEmpty {
                await withCheckedContinuation { releaseFirstWrite = $0 }
            }
            saved.append(notifications ?? "")
            return Marker()
        }
        let store = try await makeStore(api: api, unread: 6)

        let first = Task { await store.markActiveNotificationsSeen(through: "5", remainingUnread: 4, isNewer: numericNewer) }
        while releaseFirstWrite == nil { await Task.yield() }
        await store.markActiveNotificationsSeen(through: "7", remainingUnread: 2, isNewer: numericNewer)
        await store.markActiveNotificationsSeen(through: "9", remainingUnread: 0, isNewer: numericNewer)
        #expect(saved.isEmpty, "Later rows wait for the write in flight")

        releaseFirstWrite?.resume()
        await first.value
        #expect(saved == ["5", "9"], "Only the newest row seen meanwhile is written")
        #expect(store.activeUnreadCount == 0)
    }

    @Test func notificationsArrivingDuringTheWriteStayUnread() async throws {
        let api = MockMastodonAPI()
        var releaseWrite: CheckedContinuation<Void, Never>?
        api.saveMarkerHandler = { _, _ in
            await withCheckedContinuation { releaseWrite = $0 }
            return Marker()
        }
        let store = try await makeStore(api: api, unread: 3)

        let write = Task { await store.markActiveNotificationsSeen(through: "20", remainingUnread: 1, isNewer: numericNewer) }
        while releaseWrite == nil { await Task.yield() }
        store.recordIncomingNotification(sessionID: "session", notificationID: "21")
        releaseWrite?.resume()
        await write.value

        #expect(store.activeUnreadCount == 2, "One left above the seen row plus the one that just arrived")
    }

    @Test func aFailedWriteKeepsTheBadgeAndTheSameRowCanRetry() async throws {
        let api = MockMastodonAPI()
        var shouldFail = true
        api.saveMarkerHandler = { _, _ in
            if shouldFail { throw MockMastodonAPI.MockError.forcedFailure }
            return Marker()
        }
        let store = try await makeStore(api: api, unread: 2)

        await store.markActiveNotificationsSeen(through: "4", remainingUnread: 0, isNewer: numericNewer)
        #expect(store.activeUnreadCount == 2)

        shouldFail = false
        await store.markActiveNotificationsSeen(through: "4", remainingUnread: 0, isNewer: numericNewer)
        #expect(store.activeUnreadCount == 0)
    }

    @Test func feedOrdersRowsAndCountsWhatStaysUnread() async {
        let api = MockMastodonAPI()
        api.fetchNotificationsHandler = { _, _, _, _ in [item(12), item(11), item(10)] }
        let model = NotificationsViewModel(apiClient: api)
        #expect(!model.hasCurrentHead)
        await model.activate()
        #expect(model.hasCurrentHead)

        #expect(model.loadedNotificationCount(newerThan: "11") == 1)
        #expect(model.loadedNotificationCount(newerThan: "12") == 0)
        #expect(model.loadedNotificationCount(newerThan: "9") == 3, "An ID outside the list counts by value")
        #expect(model.isNotification("12", newerThan: "11") == true)
        #expect(model.isNotification("10", newerThan: "11") == false)

        var grouped = NotificationDisplayItem(from: item(10), groupKey: "group")
        grouped.merge(item(12))
        grouped.merge(item(11))
        #expect(model.newestSourceID(of: grouped) == "12", "A grouped row counts as its newest notification")
    }

    @Test func aPullWhileOpeningThePageJoinsTheRequestAlreadyRunning() async {
        let api = MockMastodonAPI()
        var requests = 0
        var releaseLoad: CheckedContinuation<Void, Never>?
        api.fetchNotificationsHandler = { _, _, _, _ in
            requests += 1
            await withCheckedContinuation { releaseLoad = $0 }
            return [item(30 + requests)]
        }
        let model = NotificationsViewModel(apiClient: api)
        let opening = Task { await model.activate(forceRefresh: true) }
        while releaseLoad == nil { await Task.yield() }
        #expect(model.isRefreshing)

        let pull = Task { await model.refresh() }
        await Task.yield()
        releaseLoad?.resume()
        let openingResult = await opening.value
        let pullResult = await pull.value

        #expect(requests == 1, "The pull shares the request instead of finding the feed busy")
        #expect(openingResult == "31")
        #expect(pullResult == "31")
        #expect(!model.isRefreshing)
    }
}
