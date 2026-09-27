import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct NotificationSnapshotTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("notification-snapshots-" + UUID().uuidString)
    }

    private func item(_ id: Int) -> NotificationItem {
        NotificationItem(id: String(id), type: "update", createdAt: Date(),
            account: ThreadReadingFixtures.status(String(id)).account, status: nil)
    }

    private func snapshot(_ ids: [Int], hasMore: Bool = true) -> NotificationSnapshotStore.Snapshot {
        .init(notifications: ids.map(item), newestID: ids.first.map(String.init),
            olderCursor: ids.last.map(String.init), hasMore: hasMore, relationships: [:],
            savedAt: Date().addingTimeInterval(-7 * 86_400))
    }

    @Test func diskRoundTripKeepsOldSnapshotsAndIsolatesAccountsAndScopes() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        let a = store.session(for: "instance-a/account-1")
        let b = store.session(for: "instance-b/account-1")
        await store.save(snapshot([3, 2]), for: a, scope: .everything)?.value
        await store.save(snapshot([1]), for: a, scope: .mentions)?.value
        await store.save(snapshot([9]), for: b, scope: .everything)?.value
        let cold = NotificationSnapshotStore(directory: directory)
        #expect(await cold.load(for: cold.session(for: a.id), scope: .everything)?.notifications.map(\.id) == ["3", "2"])
        #expect(await cold.load(for: cold.session(for: a.id), scope: .mentions)?.notifications.map(\.id) == ["1"])
        #expect(await cold.load(for: cold.session(for: b.id), scope: .everything)?.notifications.map(\.id) == ["9"])
        #expect(await cold.load(for: cold.session(for: b.id), scope: .mentions) == nil)
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(folders.count == 2)
        #expect(try folders.allSatisfy { try $0.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true })
    }

    @Test func truncationRestartsPaginationAtTheRetainedTail() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory, maximumItems: 3)
        let session = store.session(for: "a")
        await store.save(snapshot([6, 6, 5, 4, 3, 2, 1], hasMore: false), for: session, scope: .everything)?.value
        let restored = try #require(await store.load(for: session, scope: .everything))
        #expect(restored.notifications.map(\.id) == ["6", "5", "4"])
        #expect(restored.newestID == "6")
        #expect(restored.olderCursor == "4")
        #expect(restored.hasMore)
    }

    @Test func accountRemovalRejectsQueuedAndLateWritesWithoutAffectingOtherAccounts() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        let a = store.session(for: "a")
        let b = store.session(for: "b")
        store.save(snapshot([1]), for: a, scope: .everything)
        store.save(snapshot([2]), for: b, scope: .everything)
        let removal = store.removeSession(a.id)
        #expect(!store.isCurrent(a))
        #expect(store.save(snapshot([3]), for: a, scope: .everything) == nil)
        await removal.value
        let cold = NotificationSnapshotStore(directory: directory)
        #expect(await cold.load(for: cold.session(for: "a"), scope: .everything) == nil)
        #expect(await cold.load(for: cold.session(for: "b"), scope: .everything)?.notifications.first?.id == "2")
    }

    @Test func switchingAccountsInvalidatesInFlightFeedButRetainsDiskData() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        let session = store.session(for: "a")
        await store.save(snapshot([1]), for: session, scope: .everything)?.value
        store.invalidateSession(session.id)
        #expect(await store.load(for: session, scope: .everything) == nil)
        #expect(store.save(snapshot([2]), for: session, scope: .everything) == nil)
        #expect(await store.load(for: store.session(for: session.id), scope: .everything)?.notifications.first?.id == "1")
    }

    @Test func coldActivationShowsSnapshotBeforeNetworkAndKeepsItOnFailure() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        await store.save(snapshot([3, 2, 1]), for: store.session(for: "a"), scope: .everything)?.value
        let cold = NotificationSnapshotStore(directory: directory)
        let api = MockMastodonAPI()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        api.fetchNotificationsHandler = { _, sinceID, _, _ in
            #expect(sinceID == nil, "A restored snapshot must revalidate the latest page")
            signal.yield(())
            for await _ in release { break }
            throw URLError(.notConnectedToInternet)
        }
        let model = NotificationFeedStore(apiClient: api, sessionID: "a", snapshotStore: cold).model(for: .everything)
        let activation = Task { await model.activate() }
        for await _ in started { break }
        #expect(model.notifications.map(\.id) == ["3", "2", "1"])
        if case .refreshing = model.loadingState {} else { Issue.record("Cached content must remain visible during refresh") }
        resume.yield(())
        resume.finish()
        #expect(await activation.value == nil, "An offline snapshot must not acknowledge unread notifications")
        #expect(model.notifications.count == 3)
        #expect(model.refreshFailed)
        if case .loaded = model.loadingState {} else { Issue.record("Offline history must stay usable") }
    }

    @Test func coldRefreshMergesAllNewPagesAndContinuesOlderPagination() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        let session = store.session(for: "a")
        await store.save(snapshot(Array((31...60).reversed())), for: session, scope: .everything)?.value
        let api = MockMastodonAPI()
        var calls: [(String?, String?)] = []
        api.fetchNotificationsHandler = { maxID, sinceID, _, _ in
            calls.append((maxID, sinceID))
            if maxID == nil { return Array((66...95).reversed()).map(item) }
            if sinceID == "60" { return Array((61...65).reversed()).map(item) }
            #expect(maxID == "31")
            return Array((1...30).reversed()).map(item)
        }
        let model = NotificationFeedStore(apiClient: api, sessionID: "a", snapshotStore: store).model(for: .everything)
        #expect(await model.activate() == "95")
        #expect(calls.count == 2)
        #expect(calls[1].0 == "66" && calls[1].1 == "60")
        #expect(model.notifications.map(\.id) == (31...95).reversed().map(String.init))
        await model.loadMore()
        #expect(model.notifications.map(\.id) == (1...95).reversed().map(String.init))
        let persisted = await store.load(for: session, scope: .everything)
        #expect(persisted?.olderCursor == "1")
        #expect(persisted?.newestID == "95")
    }

    @Test func warmVisitsAreThrottledButPullRefreshAndUnreadActivationAreNot() async {
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchNotificationsHandler = { _, _, _, _ in
            requests += 1
            return [item(requests)]
        }
        let model = NotificationsViewModel(apiClient: api)
        await model.activate()
        await model.activate()
        #expect(requests == 1)
        await model.refresh()
        #expect(requests == 2)
        await model.activate(forceRefresh: true)
        #expect(requests == 3)
    }

    @Test func coldRevalidationRemovesDeletedNotificationsIncludingAnEmptyInbox() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        let session = store.session(for: "a")
        await store.save(snapshot([5, 4, 3]), for: session, scope: .everything)?.value
        let api = MockMastodonAPI()
        api.fetchNotificationsHandler = { _, sinceID, _, _ in
            #expect(sinceID == nil)
            return [item(5), item(3)]
        }
        let model = NotificationFeedStore(apiClient: api, sessionID: "a", snapshotStore: store).model(for: .everything)
        await model.activate()
        #expect(model.notifications.map(\.id) == ["5", "3"])
        #expect(!model.hasMore)
        api.fetchNotificationsHandler = { _, _, _, _ in [] }
        let cold = NotificationFeedStore(apiClient: api, sessionID: "a", snapshotStore: store).model(for: .everything)
        #expect(await cold.activate() == nil)
        #expect(cold.notifications.isEmpty)
        #expect(!cold.hasMore)
        #expect(await store.load(for: session, scope: .everything)?.notifications.isEmpty == true)
    }

    @Test func fullHeadRevalidationPrunesDeletedRowsButKeepsOlderLoadedHistory() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        let session = store.session(for: "a")
        await store.save(snapshot(Array((1...60).reversed()), hasMore: false), for: session, scope: .everything)?.value
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchNotificationsHandler = { _, sinceID, _, _ in
            requests += 1
            #expect(sinceID == nil)
            return ([61] + Array((31...59).reversed())).map(item)
        }
        let model = NotificationFeedStore(apiClient: api, sessionID: "a", snapshotStore: store).model(for: .everything)
        #expect(await model.activate() == "61")
        #expect(requests == 1)
        #expect(model.notifications.map(\.id) == ([61] + Array((1...59).reversed())).map(String.init))
        #expect(await store.load(for: session, scope: .everything)?.olderCursor == "1")
    }

    @Test func resolvedRequestsAreRemovedFromUnopenedSnapshotsAndLateWrites() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        let session = store.session(for: "a")
        for scope in [MastodonNotificationScope.everything, .mentions] {
            await store.save(snapshot([3, 2, 1]), for: session, scope: scope)?.value
        }
        store.removeNotifications(["2"], for: session)
        await store.save(snapshot([3, 2, 1]), for: session, scope: .everything)?.value
        let cold = NotificationSnapshotStore(directory: directory)
        for scope in [MastodonNotificationScope.everything, .mentions] {
            #expect(await cold.load(for: cold.session(for: "a"), scope: scope)?.notifications.map(\.id) == ["3", "1"])
        }
    }

    @Test func unknownSnapshotVersionFallsBackToTheNetwork() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotificationSnapshotStore(directory: directory)
        var obsolete = snapshot([1])
        obsolete.version = 999
        await store.save(obsolete, for: store.session(for: "a"), scope: .everything)?.value
        let api = MockMastodonAPI()
        api.fetchNotificationsHandler = { _, sinceID, _, _ in
            #expect(sinceID == nil)
            return [item(2)]
        }
        let model = NotificationFeedStore(apiClient: api, sessionID: "a", snapshotStore: store).model(for: .everything)
        #expect(await model.activate() == "2")
        #expect(model.notifications.map(\.id) == ["2"])
    }

    @Test func settingsClearDoesNotDeleteNotificationReadingState() async {
        let store = NotificationSnapshotStore()
        let session = store.session(for: "snapshot-clear-test-" + UUID().uuidString)
        await store.save(snapshot([1]), for: session, scope: .everything)?.value
        let settingsStorage = StorageManagementStore()
        await settingsStorage.clear()
        let cold = NotificationSnapshotStore()
        #expect(await cold.load(for: cold.session(for: session.id), scope: .everything)?.notifications.first?.id == "1")
        await store.removeSession(session.id).value
    }

    @Test func accountLifecycleKeepsSnapshotsOnSwitchAndDeletesOnRemovalAndLogout() async throws {
        let directory = directory()
        let suite = "notification-account-lifecycle-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let keychain = KeychainService(service: suite, accessGroup: nil)
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
            try? keychain.deleteAll()
        }
        let snapshots = NotificationSnapshotStore(directory: directory)
        let policySnapshots = NotificationPolicySnapshotStore(userDefaults: defaults)
        let accounts = AccountSessionStore(keychain: keychain, userDefaults: defaults,
            bootstrapStore: SharedActiveAccountSessionBootstrapStore(userDefaults: defaults),
            notificationSnapshots: snapshots,
            notificationPolicySnapshots: policySnapshots)
        let policy = ServerNotificationPolicy(
            forNotFollowing: .filter, forNotFollowers: .accept, forNewAccounts: .drop,
            forPrivateMentions: .filter, forLimitedAccounts: .drop, forBots: .accept,
            summary: .init(pendingRequestsCount: 1, pendingNotificationsCount: 2))
        let account = ThreadReadingFixtures.status("1").account
        let a = try accounts.saveSession(token: "a", account: account, instanceURL: URL(string: "https://a.example")!, activate: true)
        let aLease = snapshots.session(for: a.id)
        let aPolicyLease = policySnapshots.session(for: a.id)
        await snapshots.save(snapshot([1]), for: aLease, scope: .everything)?.value
        #expect(policySnapshots.save(policy, for: aPolicyLease))
        let b = try accounts.saveSession(token: "b", account: account, instanceURL: URL(string: "https://b.example")!, activate: true)
        #expect(!snapshots.isCurrent(aLease))
        #expect(!policySnapshots.isCurrent(aPolicyLease))
        let bLease = snapshots.session(for: b.id)
        let bPolicyLease = policySnapshots.session(for: b.id)
        await snapshots.save(snapshot([2]), for: bLease, scope: .everything)?.value
        #expect(policySnapshots.save(policy, for: bPolicyLease))
        #expect(await snapshots.load(for: snapshots.session(for: a.id), scope: .everything)?.notifications.first?.id == "1")
        let coldPolicies = NotificationPolicySnapshotStore(userDefaults: defaults)
        #expect(coldPolicies.load(for: coldPolicies.session(for: a.id))?.policy == policy)
        try accounts.removeSession(id: a.id) // Removing an inactive account must also clean up.
        await snapshots.flushPendingWrites()
        let cold = NotificationSnapshotStore(directory: directory)
        #expect(await cold.load(for: cold.session(for: a.id), scope: .everything) == nil)
        #expect(coldPolicies.load(for: coldPolicies.session(for: a.id)) == nil)
        #expect(await cold.load(for: cold.session(for: b.id), scope: .everything)?.notifications.first?.id == "2")
        #expect(coldPolicies.load(for: coldPolicies.session(for: b.id))?.policy == policy)
        accounts.clearAllSessions()
        await snapshots.flushPendingWrites()
        #expect(!snapshots.isCurrent(bLease))
        #expect(!policySnapshots.isCurrent(bPolicyLease))
        #expect(await cold.load(for: cold.session(for: b.id), scope: .everything) == nil)
        #expect(coldPolicies.load(for: coldPolicies.session(for: b.id)) == nil)
    }
}
