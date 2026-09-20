import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct ListOfflineCacheTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("list-cache-tests-\(UUID().uuidString)")
    }
    private func post(_ id: String) -> Status { ThreadReadingFixtures.status(id) }
    private var smallRender: TimelineViewModel.BootstrapConfig {
        .init(initialLoadLimit: 20, refreshLoadLimit: 20, paginationLoadLimit: 20, initialRenderCap: 2,
              cacheHydrationSoftTimeoutNanoseconds: 50_000_000, deferredFillBatchSize: 10,
              deferredFillStepNanoseconds: 1_000_000, deferredFillInitialDelayNanoseconds: 200_000_000)
    }

    @Test func diskCachesSeparateAccountsSourcesAndOpaqueListIDs() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        let cases: [(String, TimelineFilter, String)] = [
            ("a", .home, "home"), ("a", .local, "local"), ("a", .federated, "federated"),
            ("a", .list(id: "alpha"), "alpha"), ("a", .list(id: "beta"), "beta"),
            ("b", .list(id: "alpha"), "other-account"), ("a", .list(id: "../Home"), "opaque-id")]
        for (account, filter, id) in cases { await cache.set(statuses: [post(id)], for: account, filter: filter) }
        await cache.flushPendingWrites()
        let cold = TimelineCache(directory: directory)
        for (account, filter, id) in cases {
            #expect(await cold.getStatuses(for: account, filter: filter)?.map(\.id) == [id])
        }
        #expect(await cold.getStatuses(for: "missing", filter: .list(id: "alpha")) == nil)
    }

    @Test func coldMutationsAndMetadataPreserveTheirOwnListAndClearFromDisk() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        await cache.set(statuses: [post("1"), post("2")], for: "a", filter: .list(id: "alpha"))
        await cache.setLastSeenStatuses(["2"], for: "a", filter: .list(id: "alpha"))
        await cache.set(statuses: [post("other")], for: "b", filter: .list(id: "alpha"))
        await cache.flushPendingWrites()
        let cold = TimelineCache(directory: directory)
        #expect(await cold.getLastSeenStatuses(for: "a", filter: .list(id: "alpha")) == ["2"])
        await cold.append(statuses: [post("2"), post("3"), post("3")], for: "a", filter: .list(id: "alpha"))
        await cold.updateStatus(post("2").updating(favourited: true), for: "a", filter: .list(id: "alpha"))
        await cold.removeStatus(id: "1", for: "a", filter: .list(id: "alpha"))
        await cold.flushPendingWrites()
        let next = TimelineCache(directory: directory)
        #expect(await next.getStatuses(for: "a", filter: .list(id: "alpha"))?.map(\.id) == ["2", "3"])
        #expect(await next.getStatuses(for: "a", filter: .list(id: "alpha"))?.first?.favourited == true)
        #expect(await next.getLastSeenStatuses(for: "a", filter: .list(id: "alpha")) == ["2"])
        await next.clearCache(for: "a")
        await next.flushPendingWrites()
        let cleared = TimelineCache(directory: directory)
        #expect(await cleared.getStatuses(for: "a", filter: .list(id: "alpha")) == nil)
        #expect(await cleared.getLastSeenStatuses(for: "a", filter: .list(id: "alpha")) == nil)
        #expect(await cleared.getStatuses(for: "b", filter: .list(id: "alpha"))?.map(\.id) == ["other"])
    }

    @Test func failedAtomicWriteCanRetryAfterStorageRecovers() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocked directory".utf8).write(to: directory)
        let cache = TimelineCache(directory: directory)
        await cache.set(statuses: [post("retained")], for: "a", filter: .list(id: "alpha"))
        await cache.setLastSeenStatuses(["retained"], for: "a", filter: .list(id: "alpha"))
        await cache.flushPendingWrites()
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await cache.flushPendingWrites()
        let restored = TimelineCache(directory: directory)
        #expect(await restored.getStatuses(for: "a", filter: .list(id: "alpha"))?.map(\.id) == ["retained"])
        #expect(await restored.getLastSeenStatuses(for: "a", filter: .list(id: "alpha")) == ["retained"])
    }

    @Test func memoryReleaseRetainsBoundedOfflineBodiesAndHashtagsPersist() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(maxCachedStatuses: 3, directory: directory)
        await cache.set(statuses: (0..<8).map { post("\($0)") }, for: "a", filter: .list(id: "alpha"))
        await cache.set(statuses: [post("tag")], for: "a", hashtag: "Swift")
        await cache.releaseMemory()
        #expect(await cache.stats().totalStatuses == 0)
        let cold = TimelineCache(directory: directory)
        #expect(await cold.getStatuses(for: "a", filter: .list(id: "alpha"))?.map(\.id) == ["0", "1", "2"])
        #expect(await cold.getStatuses(for: "a", hashtag: "swift")?.map(\.id) == ["tag"])
        await cold.clearCache(for: "a", filter: .list(id: "alpha"))
        #expect(await TimelineCache(directory: directory).getStatuses(for: "a", filter: .list(id: "alpha")) == nil)
    }

    @Test func networkBootstrapAndCancelledRenderNeverTruncateTheOfflineTail() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        let originals = (0..<60).map { post("cached-\($0)") }
        await cache.set(statuses: originals, for: "a", filter: .list(id: "alpha"))
        ListCacheFixtureProtocol.reset()
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(), timelineType: .list(id: "alpha", title: "Renamed"),
            accountCache: AccountCache(), feedCoordinator: FeedCoordinator(), timelineCache: cache, cacheClientID: "a", bootstrapConfig: smallRender)
        await model.loadInitial()
        model.cancelBackgroundTasks()
        #expect(model.statuses.map(\.id) == ["alpha-new", "cached-0"])
        await cache.flushPendingWrites()
        let restored = TimelineCache(directory: directory)
        #expect(await restored.getStatuses(for: "a", filter: .list(id: "alpha"))?.map(\.id) == ["alpha-new"] + originals.map(\.id))
        await model.resumeCachedContentIfNeeded()
        for _ in 0..<100 {
            if model.statuses.count == 61 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.statuses.count == 61)
        #expect(Set(model.statuses.map(\.id)).count == 61)
        #expect(ListCacheFixtureProtocol.requests.count == 1)
    }

    @Test func deferredCacheFillKeepsEditsAndDeletionsFromOtherPages() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        await cache.set(statuses: (0..<8).map { post("cached-\($0)") }, for: "a", filter: .list(id: "alpha"))
        ListCacheFixtureProtocol.reset()
        let feed = FeedCoordinator()
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(), timelineType: .list(id: "alpha", title: "Alpha"),
            accountCache: AccountCache(), feedCoordinator: feed, timelineCache: cache, cacheClientID: "a", bootstrapConfig: smallRender)
        await model.loadInitial()
        feed.publishUpdate(.deletedPost("cached-5"))
        feed.publishUpdate(.post(ThreadReadingFixtures.status("cached-6", content: "<p>Edited elsewhere</p>")))
        for _ in 0..<100 {
            if model.statuses.count == 8 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.statuses.count == 8)
        #expect(!model.statuses.contains { $0.id == "cached-5" })
        #expect(model.statuses.first { $0.id == "cached-6" }?.content == "<p>Edited elsewhere</p>")
        await model.flushCacheWrites()
        let cold = TimelineCache(directory: directory)
        #expect(await cold.getStatuses(for: "a", filter: .list(id: "alpha"))?.contains { $0.id == "cached-5" } == false)
    }

    @Test func damagedAndExpiredCachesDoNotReturnStaleBodiesOrMarkers() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        await cache.set(statuses: [post("old")], for: "a", filter: .list(id: "alpha"))
        await cache.setLastSeenStatuses(["old"], for: "a", filter: .list(id: "alpha"))
        await cache.flushPendingWrites()
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "cache" })
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var records = try #require(envelope["items"] as? [[String: Any]])
        records[0]["cachedAt"] = "2000-01-01T00:00:00Z"
        envelope["items"] = records
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        let expired = TimelineCache(directory: directory)
        #expect(await expired.getStatuses(for: "a", filter: .list(id: "alpha")) == nil)
        #expect(await expired.getLastSeenStatuses(for: "a", filter: .list(id: "alpha")) == nil)
        try Data("damaged".utf8).write(to: file)
        #expect(await TimelineCache(directory: directory).getStatuses(for: "a", filter: .list(id: "alpha")) == nil)
    }

    @Test func listModelsRestoreOnlyTheirOwnCachedPostsOfflineAndRetryOnline() async {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        await cache.set(statuses: [post("alpha-cache")], for: "a", filter: .list(id: "alpha"))
        await cache.set(statuses: [post("beta-cache")], for: "a", filter: .list(id: "beta"))
        await cache.set(statuses: [post("account-b")], for: "b", filter: .list(id: "alpha"))
        await cache.flushPendingWrites()
        ListCacheFixtureProtocol.reset(offline: true)
        let client = ListCacheFixtureProtocol.makeClient()
        var models: [TimelineViewModel] = []
        for (account, list, expected) in [("a", "alpha", "alpha-cache"), ("a", "beta", "beta-cache"), ("b", "alpha", "account-b")] {
            let model = TimelineViewModel(apiClient: client, timelineType: .list(id: list, title: "Same title"),
                accountCache: AccountCache(), feedCoordinator: FeedCoordinator(), timelineCache: TimelineCache(directory: directory), cacheClientID: account)
            await model.loadInitial()
            #expect(model.statuses.map(\.id) == [expected])
            if case .failed = model.refreshState {} else { Issue.record("Missing cached-content error state") }
            models.append(model)
        }
        ListCacheFixtureProtocol.reset()
        let model = models[0]
        let result = await model.refresh()
        #expect(result.succeeded)
        #expect(model.statuses.first?.id == "alpha-new")
        if case .idle = model.refreshState {} else { Issue.record("Retry did not clear cache notice") }
    }
}
