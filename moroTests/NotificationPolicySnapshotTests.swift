import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct NotificationPolicySnapshotTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "notification-policy-snapshots-" + UUID().uuidString
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func policy(
        notFollowing: ServerNotificationPolicy.Disposition = .accept,
        notFollowers: ServerNotificationPolicy.Disposition = .filter,
        pendingRequests: Int = 0
    ) -> ServerNotificationPolicy {
        ServerNotificationPolicy(
            forNotFollowing: notFollowing,
            forNotFollowers: notFollowers,
            forNewAccounts: .drop,
            forPrivateMentions: .filter,
            forLimitedAccounts: .drop,
            forBots: .accept,
            summary: .init(
                pendingRequestsCount: pendingRequests,
                pendingNotificationsCount: pendingRequests * 2
            )
        )
    }

    @Test func snapshotsSurviveRestartAndRemainAccountScoped() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPolicySnapshotStore(userDefaults: defaults)
        let accountA = store.session(for: "account-a")
        let accountB = store.session(for: "account-b")

        #expect(store.save(policy(notFollowing: .filter), for: accountA))
        #expect(store.save(policy(notFollowing: .drop), for: accountB))

        let cold = NotificationPolicySnapshotStore(userDefaults: defaults)
        #expect(cold.load(for: cold.session(for: "account-a"))?.policy.forNotFollowing == .filter)
        #expect(cold.load(for: cold.session(for: "account-b"))?.policy.forNotFollowing == .drop)
    }

    @Test func invalidationRejectsLateWritesButRetainsLastKnownPolicy() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPolicySnapshotStore(userDefaults: defaults)
        let oldSession = store.session(for: "account-a")
        #expect(store.save(policy(notFollowing: .filter), for: oldSession))

        store.invalidateSession(oldSession.id)

        #expect(!store.isCurrent(oldSession))
        #expect(store.save(policy(notFollowing: .drop), for: oldSession) == false)
        let currentSession = store.session(for: oldSession.id)
        #expect(store.load(for: currentSession)?.policy.forNotFollowing == .filter)

        store.removeSession(oldSession.id)
        #expect(store.load(for: store.session(for: oldSession.id)) == nil)
    }

    @Test func cachedPolicyIsVisibleWhileOfflineRefreshFails() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPolicySnapshotStore(userDefaults: defaults)
        let cached = policy(notFollowing: .filter, pendingRequests: 3)
        #expect(store.save(cached, for: store.session(for: "account-a")))
        let controller = NotificationPolicyController(
            accountKey: "account-a",
            snapshotStore: store
        )
        let api = MockMastodonAPI()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        api.fetchNotificationPolicyHandler = {
            signal.yield(())
            for await _ in release { break }
            throw URLError(.notConnectedToInternet)
        }

        let refresh = Task { await controller.refresh(using: api) }
        for await _ in started { break }

        #expect(controller.policy == cached)
        #expect(controller.loadState == .loaded)
        #expect(controller.isRefreshing)

        resume.yield(())
        resume.finish()
        await refresh.value

        #expect(controller.policy == cached)
        #expect(controller.loadState == .loaded)
        #expect(controller.isRefreshing == false)
        #expect(controller.refreshError != nil)
    }

    @Test func successfulRefreshReplacesAndPersistsCachedPolicy() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPolicySnapshotStore(userDefaults: defaults)
        let cached = policy(notFollowing: .accept)
        let remote = policy(notFollowing: .drop, pendingRequests: 2)
        #expect(store.save(cached, for: store.session(for: "account-a")))
        let controller = NotificationPolicyController(
            accountKey: "account-a",
            snapshotStore: store
        )
        let api = MockMastodonAPI()
        api.fetchNotificationPolicyHandler = { remote }

        await controller.refresh(using: api)

        #expect(controller.policy == remote)
        let cold = NotificationPolicySnapshotStore(userDefaults: defaults)
        #expect(cold.load(for: cold.session(for: "account-a"))?.policy == remote)
    }

    @Test func olderRefreshCannotOverwriteANewerUserEdit() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPolicySnapshotStore(userDefaults: defaults)
        let cached = policy(notFollowing: .accept)
        #expect(store.save(cached, for: store.session(for: "account-a")))
        let controller = NotificationPolicyController(
            accountKey: "account-a",
            snapshotStore: store
        )
        let api = MockMastodonAPI()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        api.fetchNotificationPolicyHandler = {
            signal.yield(())
            for await _ in release { break }
            return cached
        }
        api.updateNotificationPolicyHandler = { $0 }

        let refresh = Task { await controller.refresh(using: api) }
        for await _ in started { break }
        await controller.save(.drop, at: \.forNotFollowing, using: api)
        resume.yield(())
        resume.finish()
        await refresh.value

        #expect(controller.policy?.forNotFollowing == .drop)
        let cold = NotificationPolicySnapshotStore(userDefaults: defaults)
        #expect(cold.load(for: cold.session(for: "account-a"))?.policy.forNotFollowing == .drop)
    }

    @Test func unsupportedServerClearsAnObsoleteSnapshot() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPolicySnapshotStore(userDefaults: defaults)
        #expect(store.save(policy(), for: store.session(for: "account-a")))
        let controller = NotificationPolicyController(
            accountKey: "account-a",
            snapshotStore: store
        )
        let api = MockMastodonAPI()
        api.fetchNotificationPolicyHandler = {
            throw APIError.http(statusCode: 404, data: nil)
        }

        await controller.refresh(using: api)

        #expect(controller.loadState == .unsupported)
        #expect(controller.policy == nil)
        #expect(store.load(for: store.session(for: "account-a")) == nil)
    }

    @Test func olderUnsupportedRefreshCannotClearANewerUserEdit() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPolicySnapshotStore(userDefaults: defaults)
        #expect(store.save(policy(), for: store.session(for: "account-a")))
        let controller = NotificationPolicyController(
            accountKey: "account-a",
            snapshotStore: store
        )
        let api = MockMastodonAPI()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        api.fetchNotificationPolicyHandler = {
            signal.yield(())
            for await _ in release { break }
            throw APIError.http(statusCode: 404, data: nil)
        }
        api.updateNotificationPolicyHandler = { $0 }

        let refresh = Task { await controller.refresh(using: api) }
        for await _ in started { break }
        await controller.save(.drop, at: \.forNotFollowing, using: api)
        resume.yield(())
        resume.finish()
        await refresh.value

        #expect(controller.loadState == .loaded)
        #expect(controller.policy?.forNotFollowing == .drop)
        let cold = NotificationPolicySnapshotStore(userDefaults: defaults)
        #expect(cold.load(for: cold.session(for: "account-a"))?.policy.forNotFollowing == .drop)
    }
}
