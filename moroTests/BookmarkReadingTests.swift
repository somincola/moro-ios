import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct BookmarkReadingTests {
    private func storage() -> (BookmarkLibraryStore, URL, UserDefaults, String) {
        let name = "bookmark-tests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let defaults = UserDefaults(suiteName: name)!
        return (BookmarkLibraryStore(accountKey: "a", directory: directory, defaults: defaults), directory, defaults, name)
    }

    @Test func pagesUseBookmarkRelationshipCursorDeduplicateAndStopOnRepeatedLink() async throws {
        BookmarkFixtureProtocol.reset(repeatsCursor: true)
        let model = BookmarksViewModel(apiClient: BookmarkFixtureProtocol.makeClient(), feedCoordinator: FeedCoordinator())
        await model.loadInitial()
        #expect(model.statuses.map(\.id) == ["b1", "b2"])
        #expect(model.hasMore)
        await model.loadMore()
        #expect(model.statuses.map(\.id) == ["b1", "b2", "b3"])
        #expect(!model.hasMore)
        let count = BookmarkFixtureProtocol.requests.count
        await model.loadInitial()
        await model.loadMore()
        #expect(BookmarkFixtureProtocol.requests.count == count)
        let url = try #require(BookmarkFixtureProtocol.requests.last?.url)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "max_id" }?.value == "bookmark:cursor")
        #expect(BookmarkFixtureProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer bookmark-fixture" })
    }

    @Test func missingLinkEndsPagesAndFailedPageRetriesTheSameCursor() async {
        BookmarkFixtureProtocol.reset(sendsNextLink: false)
        let noLink = BookmarksViewModel(apiClient: BookmarkFixtureProtocol.makeClient(), feedCoordinator: FeedCoordinator())
        await noLink.loadInitial()
        #expect(!noLink.hasMore)
        BookmarkFixtureProtocol.reset()
        let model = BookmarksViewModel(apiClient: BookmarkFixtureProtocol.makeClient(), feedCoordinator: FeedCoordinator())
        await model.loadInitial()
        BookmarkFixtureProtocol.failNext("/api/v1/bookmarks")
        await model.loadMore()
        #expect(model.loadMoreFailed && model.hasMore)
        #expect(model.statuses.count == 2)
        await model.loadMore()
        #expect(!model.loadMoreFailed && model.statuses.count == 3)
        let requests = BookmarkFixtureProtocol.requests.suffix(2)
        #expect(Set(requests.compactMap(\.url)).count == 1)
    }

    @Test func searchIncludesFullLinkTargetsAndCombinesWithExplicitReadFilter() async {
        BookmarkFixtureProtocol.reset()
        let model = BookmarksViewModel(apiClient: BookmarkFixtureProtocol.makeClient(), feedCoordinator: FeedCoordinator())
        await model.loadInitial()
        model.searchQuery = "secret=1"
        #expect(model.filteredStatuses.map(\.id) == ["b1"])
        model.setRead(true, status: model.statuses[0])
        model.readingFilter = .unread
        #expect(model.filteredStatuses.isEmpty)
        model.readingFilter = .read
        #expect(model.filteredStatuses.map(\.id) == ["b1"])
        model.searchQuery = "moro"
        model.readingFilter = .all
        #expect(model.filteredStatuses.count == 2)
        model.searchQuery = "旅行"
        #expect(model.filteredStatuses.map(\.id) == ["b2"])
    }

    @Test func boundedCacheSurvivesRestartAndKeepsAccountsAndReadFlagsSeparate() throws {
        let (library, directory, defaults, name) = storage()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        library.cache((0..<210).map { ThreadReadingFixtures.status("\($0)").updating(bookmarked: true) }, complete: true)
        library.setRead(true, id: "205")
        #expect(library.cachedStatuses.count == 200)
        let restored = BookmarkLibraryStore(accountKey: "a", directory: directory, defaults: defaults)
        #expect(restored.cachedStatuses.map(\.id) == (0..<200).map(String.init))
        #expect(restored.readIDs == ["205"])
        let other = BookmarkLibraryStore(accountKey: "b", directory: directory, defaults: defaults)
        #expect(other.cachedStatuses.isEmpty && other.readIDs.isEmpty)
        library.cache([ThreadReadingFixtures.status("new")], complete: false)
        #expect(library.cachedStatuses.first?.id == "new" && library.cachedStatuses.count == 200)
        library.cache([], complete: true)
        #expect(BookmarkLibraryStore(accountKey: "a", directory: directory, defaults: defaults).cachedStatuses.isEmpty)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("corrupt".utf8).write(to: file)
        #expect(BookmarkLibraryStore(accountKey: "a", directory: directory, defaults: defaults).readIDs == ["205"])
    }

    @Test func failedRemovalPreservesCacheAndReadStateThenConfirmationUpdatesOtherReaders() async {
        let (library, directory, defaults, name) = storage()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        BookmarkFixtureProtocol.reset(failures: ["/api/v1/statuses/b1/unbookmark": 1])
        let feed = FeedCoordinator()
        let client = BookmarkFixtureProtocol.makeClient()
        let model = BookmarksViewModel(apiClient: client, library: library, feedCoordinator: feed)
        let other = BookmarksViewModel(apiClient: client, feedCoordinator: feed)
        await model.loadInitial(); await other.loadInitial()
        let first = model.statuses[0]
        model.setRead(true, status: first)
        await model.removeBookmark(first)
        #expect(model.statuses.count == 2 && model.readIDs.contains("b1"))
        #expect(library.cachedStatuses.count == 2 && library.readIDs.contains("b1"))
        #expect(model.transientErrorMessage != nil && model.removingIDs.isEmpty)
        await model.removeBookmark(first)
        #expect(model.statuses.map(\.id) == ["b2"])
        #expect(other.statuses.map(\.id) == ["b2"])
        #expect(library.cachedStatuses.map(\.id) == ["b2"] && library.readIDs.isEmpty)
        await model.removeBookmark(model.statuses[0])
        await model.loadMore()
        #expect(model.statuses.map(\.id) == ["b3"])
    }

    @Test func offlineRestartShowsCachedBodiesAndReadStateAndCanRetryOnline() async {
        let (library, directory, defaults, name) = storage()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        library.cache(BookmarkFixtureProtocol.statuses, complete: true)
        library.setRead(true, id: "b1")
        BookmarkFixtureProtocol.reset(offline: true)
        let restored = BookmarkLibraryStore(accountKey: "a", directory: directory, defaults: defaults)
        let model = BookmarksViewModel(apiClient: BookmarkFixtureProtocol.makeClient(), library: restored, feedCoordinator: FeedCoordinator())
        #expect(model.statuses.count == 3)
        await model.loadInitial()
        #expect(model.isOfflineSnapshot && model.statuses.count == 3)
        model.readingFilter = .read
        #expect(model.filteredStatuses.map(\.id) == ["b1"])
        BookmarkFixtureProtocol.reset()
        await model.refresh()
        #expect(!model.isOfflineSnapshot && model.statuses.count == 2)
        #expect(model.readIDs == ["b1"])
    }
}
