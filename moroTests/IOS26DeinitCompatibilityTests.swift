import SwiftUI
import UIKit
import XCTest
@testable import moro

private enum DeinitCallbackContext {
    @TaskLocal static var marker: String?
}

/// Deliberately synchronous XCTest: Swift Testing / async tests run inside a Task
/// and can hide the iOS 26.0–26.2 isolated-deinit runtime failure. Keep the last
/// release inside a task-local scope on a thread with no current Swift Task.
@MainActor
final class IOS26DeinitCompatibilityTests: XCTestCase {
    func testPostCardStateIsReleasedInSynchronousCallbacks() {
        for _ in 0..<20 {
            assertReleased { StatusTranslationViewModel() }
            assertReleased {
                ContentConcealViewModel(statusID: "post", hasContentWarning: true, spoilerText: "CW")
            }
            assertReleased { ScrollStateManager() }
            assertReleased { PostActionSurfaceCenter() }
            assertReleased { TranslationLanguagesStore() }
        }
    }

    func testNotificationFeedReleasesBothScopeModels() {
        weak var all: NotificationsViewModel?
        weak var mentions: NotificationsViewModel?
        assertReleased {
            let store = NotificationFeedStore(apiClient: MockMastodonAPI())
            all = store.model(for: .everything)
            mentions = store.model(for: .mentions)
            XCTAssertNotNil(all)
            XCTAssertNotNil(mentions)
            XCTAssertFalse(all === mentions)
            return store
        }
        XCTAssertNil(all)
        XCTAssertNil(mentions)
    }

    func testTimelineStoresReleaseTheirOwnedModelsAndSessions() {
        weak var model: TimelineViewModel?
        assertReleased {
            let store = PinnedTimelineViewModelStore()
            model = store.viewModel(for: .local, apiClient: MockMastodonAPI(), cacheClientID: "deinit-test")
            XCTAssertNotNil(model)
            store.prune(keeping: [])
            XCTAssertNil(model)
            model = store.viewModel(for: .federated, apiClient: MockMastodonAPI(), cacheClientID: "deinit-test")
            return store
        }
        XCTAssertNil(model)

        weak var session: TimelinePageSession?
        assertReleased {
            let store = TimelinePageSessionStore()
            session = store.session(for: .home)
            session?.recordContentOffset(160)
            store.prunePinnedSessions(keeping: [])
            XCTAssertEqual(store.session(for: .home).contentOffsetY, 160)
            return store
        }
        XCTAssertNil(session)
    }

    func testScrollBridgeReplacesAndReleasesWeakWrappers() {
        assertReleased {
            let bridge = TimelineScrollBridge()
            // Replacement releases the private wrappers while the owner lives.
            // Testing only the owner's deinit would miss this hot path.
            for _ in 0..<20 {
                let scroll = UIScrollView()
                let row = TimelineRowAnchorView()
                row.statusID = "same-row"
                bridge.register(scroll, for: .home)
                bridge.rowDidLayout(row, for: .home)
            }
            return bridge
        }
        assertReleased { TimelineScrollResolverView() }
    }

    func testPagerCoordinatorReleasesItsPrivateHostingControllers() {
        assertReleased {
            TimelinePagerHost.Coordinator(
                selection: .constant(.home),
                pages: TimelineType.builtin.map { TimelinePagerPage(type: $0, view: AnyView(EmptyView())) },
                onTransitionStarted: { _ in }, onPagePresented: { _ in }
            )
        }
        assertReleased {
            let controller = TimelineSelectionViewController()
            controller.display(TimelinePageHostingController(timelineType: .home, rootView: AnyView(EmptyView())))
            controller.display(TimelinePageHostingController(timelineType: .local, rootView: AnyView(EmptyView())))
            return controller
        }
    }

    func testMainShellReleasesItsNavigationAndHostingHierarchy() {
        assertReleased {
            let controller = MainShellViewController(
                coordinator: RootTabCoordinator(), theme: MoroTheme(), unreadInboxCount: 0,
                currentUserAvatarURL: nil, contentVersion: "deinit-test",
                homeView: AnyView(EmptyView()), exploreView: AnyView(EmptyView()),
                inboxView: AnyView(EmptyView()), meView: AnyView(EmptyView()),
                routeView: { _, _ in AnyView(EmptyView()) }
            )
            controller.loadViewIfNeeded()
            return controller
        }
    }

    func testSearchAndMediaUIKitObjectsAreReleased() {
        assertReleased { SearchLandingPlaceholderView(frame: .zero) }
        assertReleased { SearchCenterStateView(iconName: nil, title: nil, showsIndicator: false, animationStyle: .none) }
        assertReleased { SearchLoadingMoreCell(style: .default, reuseIdentifier: nil) }
        assertReleased { SearchResultLineCell(style: .default, reuseIdentifier: nil) }
        assertReleased { SearchScopeMenuButton(frame: .zero) }
        assertReleased { ImagePreviewPageView(frame: .zero) }
        assertReleased { ImagePreviewScrollView(frame: .zero) }
        assertReleased { PlayerLayerView(frame: .zero) }
        assertReleased { SDWebRemoteImage.Coordinator() }
    }

    func testScreenModelsAndTheirSubscriptionsAreReleased() {
        let api = MockMastodonAPI()
        assertReleased { ProfileViewModel(apiClient: api, accountID: "account", accountCache: AccountCache(), feedCoordinator: FeedCoordinator()) }
        assertReleased { ProfileConnectionsViewModel(accountID: "account", kind: .followers, apiClient: api) }
        assertReleased { HashtagViewModel(apiClient: api, hashtag: "swift", accountCache: AccountCache(), feedCoordinator: FeedCoordinator()) }
        assertReleased { FollowedTopicsViewModel(apiClient: api) }
        assertReleased { TopicFollowModel(apiClient: api, name: "swift") }
        assertReleased { ListsViewModel(apiClient: api) }
        assertReleased { FavouritesViewModel(apiClient: api) }
        assertReleased { BookmarksViewModel(apiClient: api) }
        assertReleased { AnnouncementsViewModel(apiClient: api) }
        assertReleased { ScheduledStatusesViewModel(apiClient: api) }
        assertReleased { DirectMessagesViewModel(apiClient: api) }
        assertReleased { ConversationDetailViewModel(conversation: Conversation(id: "conversation", unread: false, accounts: [], lastStatus: nil), apiClient: api) }
        assertReleased { ComposeViewModel(context: .newPost, apiClient: api, feedCoordinator: FeedCoordinator()) }
        assertReleased { ComposeAutocompleteModel(apiClient: api) }
        assertReleased { FeaturedTagsViewModel(apiClient: api) }
        assertReleased { FiltersSettingsViewModel(apiClient: api) }
        assertReleased { PostInteractionService(apiClient: api, feedCoordinator: FeedCoordinator()) }
        assertReleased { PostMenuActionCenter(apiClient: api) }
    }

    func testNotificationSettingsReleaseTheirInjectedSnapshotStore() throws {
        let suite = "IOS26DeinitCompatibilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        weak var snapshots: NotificationPolicySnapshotStore?
        assertReleased {
            let store = NotificationPolicySnapshotStore(userDefaults: defaults)
            snapshots = store
            return NotificationPolicyController(accountKey: "account", snapshotStore: store)
        }
        XCTAssertNil(snapshots)
        assertReleased { SearchLibraryStore(accountKey: "account", defaults: defaults) }
        assertReleased { ProfilePresentationPreferences(defaults: defaults) }
    }

    func testThreadCacheEvictionAndPostDetailModelsAreReleased() {
        let api = MockMastodonAPI()
        let status = makeStatus(id: "first")
        assertReleased { StatusDataController(status: status, client: api) }
        assertReleased { StatusDetailViewModel(status: status, apiClient: api, threadCache: ThreadCache(), accountCache: AccountCache(), feedCoordinator: FeedCoordinator()) }
        assertReleased { ReportViewModel(apiClient: api, status: status) }
        assertReleased { ReportViewModel(apiClient: api, account: status.account) }

        weak var evicted: ThreadedConversationModel?
        weak var remaining: ThreadedConversationModel?
        assertReleased {
            let cache = ThreadCache(maxCacheSize: 1)
            cache.set(ThreadedConversationModel(focusedStatus: status, context: StatusContext(ancestors: [], descendants: [])), for: "first")
            evicted = cache.get(statusID: "first")
            XCTAssertNotNil(evicted)
            cache.set(ThreadedConversationModel(focusedStatus: makeStatus(id: "second"), context: StatusContext(ancestors: [], descendants: [])), for: "second")
            remaining = cache.get(statusID: "second")
            XCTAssertNil(evicted)
            XCTAssertNotNil(remaining)
            return cache
        }
        XCTAssertNil(remaining)
    }

    func testParserCacheChurnAndEmojiTreeReleaseInCallbacks() {
        inSynchronousCallback {
            // Exceed both cache limits to exercise private value-box eviction.
            let prefix = UUID().uuidString
            for index in 0..<1400 {
                let text = "\(prefix)-\(index)"
                XCTAssertFalse(ContentParser.parseToElements(html: "<p>\(text)</p>").isEmpty)
                XCTAssertEqual(AccountDisplayNameParser.parse(displayName: text, fallbackUsername: "user", emojis: []).plainText, text)
            }
            autoreleasepool {
                var trie = EmojiTrie()
                let url = URL(string: "https://example.invalid/emoji.png")!
                let emoji = CustomEmoji(shortcode: "wave", url: url, staticURL: url, visibleInPicker: true, category: nil)
                trie.insert("wave", value: emoji)
                trie.insert("warm", value: emoji)
                XCTAssertEqual(trie.search("wa").count, 2)
                XCTAssertTrue(trie.search("missing").isEmpty)
            }
        }
    }

    private func makeStatus(id: String) -> Status {
        let account = Account(
            id: "account", username: "user", acct: "user@example.invalid", displayName: "User",
            note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
            followersCount: 0, followingCount: 0, statusesCount: 0
        )
        return Status(
            id: id, content: "<p>Compatibility test</p>", createdAt: Date(), account: account,
            mediaAttachments: [], favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
            bookmarked: false, favourited: false, reblogged: false, reblog: nil, quote: nil,
            inReplyToID: nil, spoilerText: nil, visibility: "public", language: nil,
            mentions: nil, tags: nil, card: nil, poll: nil, filtered: nil, pinned: nil
        )
    }

    private func inSynchronousCallback(_ body: () -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(Thread.isMainThread, file: file, line: line)
        withUnsafeCurrentTask { task in
            XCTAssertNil(task, "An async test would mask the affected runtime path", file: file, line: line)
        }
        DeinitCallbackContext.$marker.withValue("UIKit callback") {
            body()
        }
    }

    private func assertReleased<T: AnyObject>(file: StaticString = #filePath, line: UInt = #line, make: () -> T) {
        inSynchronousCallback({
            weak var released: T?
            autoreleasepool {
                var object: T? = make()
                released = object
                XCTAssertNotNil(released, file: file, line: line)
                object = nil
            }
            XCTAssertNil(released, "\(T.self) escaped synchronous teardown", file: file, line: line)
        }, file: file, line: line)
    }
}
