import Combine
import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import moro

@MainActor
struct PushNotificationTests {
    @Test func payloadAcceptsRelaySessionAndNumericOrStringIDs() {
        let payload = PushNotificationPayload(userInfo: [
            "x": "server%3Aaccount", "notification_id": NSNumber(value: Int64.max),
            "notification_type": " MENTION ", "status_url": "https://remote.example/@person/123",
        ])
        #expect(payload.sessionID == "server:account")
        #expect(payload.notificationID == String(Int64.max))
        #expect(payload.notificationType == "mention")
        #expect(payload.statusURL?.host == "remote.example")
        #expect(PushNotificationPayload(userInfo: ["notification_id": "123"]).notificationID == "123")
    }

    @Test func malformedAndEncryptedOnlyPayloadsRemainSafeToOpen() {
        for value: Any in [NSNull(), true, 1.5, "../statuses/123", "", ["id": "123"]] {
            #expect(PushNotificationPayload(userInfo: ["notification_id": value]).notificationID == nil)
        }
        for url in ["javascript:alert(1)", "file:///etc/passwd", "https://user:pass@example.com/@a/123"] {
            #expect(PushNotificationPayload(userInfo: ["url": url]).statusURL == nil)
        }
        let payload = PushNotificationPayload(userInfo: ["aps": ["alert": "New notification"], "p": "ciphertext", "x": "a"])
        #expect(payload.sessionID == "a")
        #expect(payload.notificationID == nil)
    }

    @Test func backgroundResponseCompletesOnceOnMainAfterQueuing() async throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = PushRegistrationCenter(notificationStore: store)
        let payload = PushNotificationPayload(userInfo: ["x": "a", "notification_id": "123"])
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        await Task.detached {
            center.handleResponse(payload, actionIdentifier: UNNotificationDefaultActionIdentifier) {
                continuation.yield(Thread.isMainThread)
                continuation.finish()
            }
        }.value
        var results = [Bool]()
        for await result in stream { results.append(result) }
        #expect(results == [true])
        #expect(store.pendingOpenRequest?.payload == payload)
    }

    @Test func dismissAndUnknownActionsCompleteWithoutNavigating() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = PushRegistrationCenter(notificationStore: store)
        for action in [UNNotificationDismissActionIdentifier, "unknown-action"] {
            let (stream, continuation) = AsyncStream<Bool>.makeStream()
            center.handleResponse(PushNotificationPayload(userInfo: [:]), actionIdentifier: action) {
                continuation.yield(Thread.isMainThread)
                continuation.finish()
            }
            for await onMain in stream { #expect(onMain) }
            #expect(store.pendingOpenRequest == nil)
        }
    }

    @Test func coldLaunchRequestSurvivesActivationAndOldConsumption() async throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.handleNotificationResponse(PushNotificationPayload(userInfo: ["x": "b", "notification_id": "1"]))
        let first = try #require(store.pendingOpenRequest)
        let api = MockMastodonAPI()
        await store.activate(sessionID: "a", availableSessionIDs: ["a", "b"], apiClient: api)
        #expect(store.pendingOpenRequest?.id == first.id)
        #expect(store.pendingOpenRequest?.sessionID == "b")
        store.handleNotificationResponse(PushNotificationPayload(userInfo: ["x": "b", "notification_id": "2"]))
        let second = try #require(store.pendingOpenRequest)
        store.consumePendingNotificationOpen(id: first.id)
        #expect(store.pendingOpenRequest?.id == second.id)
        store.consumePendingNotificationOpen(id: second.id)
        #expect(store.pendingOpenRequest == nil)
        store.handleNotificationResponse(first.payload)
        #expect(store.pendingOpenRequest?.id != first.id)
        #expect(store.pendingOpenRequest?.id != second.id)
    }

    @Test func notificationIDLoadsItsPostWithoutScanningRecentNotifications() async {
        let api = MockMastodonAPI()
        api.fetchNotificationHandler = { id in
            #expect(id == "old-notification")
            return notification(id: id, status: post())
        }
        api.fetchNotificationsHandler = { _, _, _ in
            Issue.record("Push opening must not scan only the latest notifications")
            return []
        }
        let result = await PushNotificationResolver.resolve(
            PushNotificationPayload(userInfo: ["notification_id": "old-notification"]), apiClient: api)
        guard case .status(let status) = result else { Issue.record("Expected post detail"); return }
        #expect(status.id == "post-123")
    }

    @Test func unknownDeletedAndOfflineNotificationsFallBackToInbox() async {
        for error: Error in [APIError.http(statusCode: 404, data: nil), APIError.http(statusCode: 501, data: nil), URLError(.notConnectedToInternet)] {
            let api = MockMastodonAPI()
            api.fetchNotificationHandler = { _ in throw error }
            let result = await PushNotificationResolver.resolve(
                PushNotificationPayload(userInfo: ["notification_id": "123"]), apiClient: api)
            guard case .notifications = result else { Issue.record("Expected safe Inbox fallback"); return }
        }
        let result = await PushNotificationResolver.resolve(PushNotificationPayload(userInfo: [:]), apiClient: MockMastodonAPI())
        guard case .notifications = result else { Issue.record("Missing data should open Inbox"); return }
    }

    @Test func followOpensProfileButFollowRequestStaysInNotifications() async {
        let api = MockMastodonAPI()
        api.fetchNotificationHandler = { id in notification(id: id, type: "follow") }
        let payload = PushNotificationPayload(userInfo: ["notification_id": "123"])
        guard case .profile(let account) = await PushNotificationResolver.resolve(payload, apiClient: api) else {
            Issue.record("Expected followed-by account"); return
        }
        #expect(account.id == "person")
        api.fetchNotificationHandler = { id in notification(id: id, type: "follow_request") }
        guard case .notifications = await PushNotificationResolver.resolve(payload, apiClient: api) else {
            Issue.record("Follow requests need their Inbox actions"); return
        }
    }

    @Test func directMessageWithoutExactConversationOpensMessages() async {
        let api = MockMastodonAPI()
        api.fetchNotificationHandler = { id in notification(id: id, status: post(visibility: "direct")) }
        api.fetchConversationsHandler = { _, _, _ in [] }
        let result = await PushNotificationResolver.resolve(PushNotificationPayload(userInfo: ["notification_id": "123"]), apiClient: api)
        guard case .messages = result else { Issue.record("Expected message list fallback"); return }
    }

    @Test func cancelledLookupCannotReturnPostAndFallbackClearsOldDetail() async {
        let api = MockMastodonAPI()
        let (started, signal) = AsyncStream<Void>.makeStream()
        api.fetchNotificationHandler = { id in
            signal.yield(())
            try? await Task.sleep(for: .seconds(10))
            return notification(id: id, status: post())
        }
        let task = Task { await PushNotificationResolver.resolve(PushNotificationPayload(userInfo: ["notification_id": "123"]), apiClient: api) }
        for await _ in started { break }
        task.cancel()
        guard case .notifications = await task.value else { Issue.record("Cancelled task opened post"); return }
        let coordinator = RootTabCoordinator()
        coordinator.openPushNotification(.status(post()))
        #expect(coordinator.inboxRouter.path.count == 1)
        coordinator.openPushNotification(.notifications)
        #expect(coordinator.selectedTab == .inbox)
        #expect(coordinator.inboxRouter.path.isEmpty)
    }

    private func makeStore() -> (NotificationUnreadStore, UserDefaults, String) {
        let suite = "PushNotificationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        return (NotificationUnreadStore(userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(), badgeSetter: { _ in }), defaults, suite)
    }

    private func account() -> Account {
        Account(id: "person", username: "person", acct: "person", displayName: "Person", note: "",
            avatar: "", avatarStatic: "", header: "", headerStatic: "", followersCount: 0, followingCount: 0, statusesCount: 1)
    }

    private func post(visibility: String = "public") -> Status {
        Status(id: "post-123", content: "<p>Push target post</p>", createdAt: Date(), account: account(),
            mediaAttachments: [], favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
            bookmarked: false, favourited: false, reblogged: false, visibility: visibility)
    }

    private func notification(id: String, type: String = "mention", status: Status? = nil) -> NotificationItem {
        NotificationItem(id: id, type: type, createdAt: Date(), account: account(), status: status)
    }
}
