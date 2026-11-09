import Foundation
import Testing
@testable import moro

/// Automatic refreshes: fresh content isn't asked for again, failures back off, offline
/// pauses and catches up. Signals and the reader's own refreshes are never held back.
@Suite @MainActor
struct AutoRefreshScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func freshContentIsNotAskedForAgainUntilItsTTLPasses() {
        var schedule = AutoRefreshSchedule(ttl: 300)
        #expect(schedule.isDue(now: start, isOffline: false), "Nothing loaded yet")
        schedule.recordSuccess(at: start)
        #expect(!schedule.isDue(now: start.addingTimeInterval(299), isOffline: false))
        #expect(schedule.isDue(now: start.addingTimeInterval(300), isOffline: false))
    }

    @Test func automaticFailuresWaitLongerEachTimeAndOneSuccessResets() {
        var schedule = AutoRefreshSchedule(ttl: 300)
        schedule.recordSuccess(at: start)
        var now = start.addingTimeInterval(400)
        for (failure, wait) in [30.0, 60, 120, 300, 300].enumerated() {
            schedule.recordFailure(at: now, automatic: true)
            #expect(schedule.backoffDelay == wait, "Failure \(failure + 1)")
            #expect(!schedule.isDue(now: now.addingTimeInterval(wait - 1), isOffline: false))
            #expect(schedule.isDue(now: now.addingTimeInterval(wait), isOffline: false))
            now = now.addingTimeInterval(wait)
        }
        schedule.recordSuccess(at: now)
        #expect(schedule.backoffDelay == nil)
        #expect(!schedule.isDue(now: now.addingTimeInterval(1), isOffline: false), "Fresh again")
    }

    @Test func theReadersOwnRefreshEndsTheBackoff() {
        var schedule = AutoRefreshSchedule(ttl: 300)
        schedule.recordFailure(at: start, automatic: true)
        schedule.recordFailure(at: start, automatic: true)
        #expect(schedule.backoffDelay == 60)
        schedule.recordFailure(at: start, automatic: false)
        #expect(schedule.backoffDelay == nil, "A failed pull is not held against the next automatic check")

        schedule.recordFailure(at: start, automatic: true)
        schedule.resetBackoff()
        #expect(schedule.isDue(now: start, isOffline: false))
    }

    @Test func offlineChecksAreSkippedAndOwedUntilTheConnectionReturns() {
        var schedule = AutoRefreshSchedule(ttl: 300)
        schedule.recordSuccess(at: start)
        let later = start.addingTimeInterval(10)
        let whileOffline = schedule.shouldRefresh(now: later, isOffline: true)
        #expect(!whileOffline)
        #expect(schedule.owesCatchUp)
        #expect(!schedule.isDue(now: later, isOffline: true), "Still nothing while offline")
        let backOnline = schedule.shouldRefresh(now: later, isOffline: false)
        #expect(backOnline, "Back online, the skipped check runs even though the content is within its TTL")
        schedule.recordSuccess(at: later)
        #expect(!schedule.owesCatchUp)
        let afterCatchUp = schedule.shouldRefresh(now: later.addingTimeInterval(1), isOffline: false)
        #expect(!afterCatchUp)
    }

    // MARK: - Notifications

    private func item(_ id: Int) -> NotificationItem {
        NotificationItem(id: String(id), type: "update", createdAt: Date(),
            account: ThreadReadingFixtures.status(String(id)).account, status: nil)
    }

    @Test func notificationsSkipFreshVisitsButNotBadgesOrPulls() async {
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchNotificationsHandler = { _, _, _, _ in
            requests += 1
            return [item(requests)]
        }
        let model = NotificationsViewModel(apiClient: api, automaticRefreshTTL: 300, isOffline: { false })
        await model.activate()
        await model.activate()
        #expect(requests == 1, "Coming back within the TTL asks nothing")
        await model.activate(forceRefresh: true)
        #expect(requests == 2, "Unread notifications always refresh")
        await model.refresh()
        #expect(requests == 3, "So does a pull")
    }

    @Test func notificationsBackOffAfterAutomaticFailuresUntilThePull() async {
        let api = MockMastodonAPI()
        var requests = 0
        var failing = false
        api.fetchNotificationsHandler = { _, _, _, _ in
            requests += 1
            if failing { throw MockMastodonAPI.MockError.forcedFailure }
            return [item(requests)]
        }
        let model = NotificationsViewModel(apiClient: api, automaticRefreshTTL: 0, isOffline: { false })
        await model.activate()
        failing = true
        await model.activate()
        #expect(requests == 2)
        #expect(model.refreshFailed)

        await model.activate()
        #expect(requests == 2, "The next automatic check waits out the backoff")

        failing = false
        await model.refresh()
        #expect(requests == 3, "The reader's pull is never held back")
        await model.activate()
        #expect(requests == 4, "And it ends the backoff (TTL 0 here)")
    }

    @Test func notificationsPauseOfflineAndCatchUpOnceBackOnline() async {
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchNotificationsHandler = { _, _, _, _ in
            requests += 1
            return [item(requests)]
        }
        var offline = false
        let model = NotificationsViewModel(apiClient: api, automaticRefreshTTL: 300, isOffline: { offline })
        await model.activate()
        #expect(requests == 1)

        offline = true
        await model.activate(forceRefresh: true)
        #expect(requests == 1, "Even a badge doesn't ask while offline")

        offline = false
        await model.activate()
        #expect(requests == 2, "The skipped check runs once the connection is back")
        await model.activate()
        #expect(requests == 2, "Then it is fresh again")
    }
}
