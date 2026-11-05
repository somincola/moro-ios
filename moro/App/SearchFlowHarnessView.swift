#if DEBUG
import SwiftUI

/// Production search and route destinations, using an isolated HTTP transport.
struct SearchFlowHarnessView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var tabs = RootTabCoordinator(selectedTab: .explore)
    @StateObject private var appState = AppState()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var accountKey = "ui-search-a"
    @State private var avatarsPrepared = false
    @State private var autoplayAvatars = true
    private let client = SearchFixtureProtocol.makeClient()
    private let testsAnimatedAvatars = ProcessInfo.processInfo.environment["UITEST_ANIMATED_LIST_AVATARS"] == "1"

    private static let seed: Void = {
        for key in ["ui-search-a", "ui-search-b"] {
            UserDefaults.standard.removeObject(forKey: "search_library_v1.\(key)")
        }
        let a = SearchLibraryStore(accountKey: "ui-search-a")
        a.record(query: "Moro", scope: .all)
        let b = SearchLibraryStore(accountKey: "ui-search-b")
        b.record(query: "Other account", scope: .hashtags)
    }()

    init() { _ = Self.seed }

    var body: some View {
        Group {
            if testsAnimatedAvatars {
                VStack(spacing: 0) {
                    Toggle("Autoplay GIFs", isOn: $autoplayAvatars)
                        .accessibilityIdentifier("listAvatars.autoplay")
                        .padding(.horizontal)
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text("active:\(TimelineAvatarAnimationPool.shared.activeCount) warm:\(TimelineAvatarAnimationPool.shared.warmCount)")
                            .font(.caption.monospacedDigit())
                            .accessibilityIdentifier("listAvatars.resources")
                    }
                    if avatarsPrepared { harnessContent }
                }
                .task {
                    do {
                        try await TimelineMediaFixture.prepare()
                        avatarsPrepared = true
                    } catch { AppFeedbackCenter.shared.showError(error.localizedDescription) }
                }
            } else { harnessContent }
        }
        .environmentObject(appState)
        .moroTheme(theme)
    }

    private var harnessContent: some View {
        Group {
            if ProcessInfo.processInfo.environment["UITEST_SEARCH_NATIVE_SHELL"] == "1" {
                MainShellContainerRepresentable(
                    coordinator: tabs, theme: theme, unreadInboxCount: 0,
                    currentUserAvatarURL: nil, contentVersion: accountKey,
                    homeView: AnyView(Text("Home")),
                    exploreView: AnyView(searchRoot(router: tabs.exploreRouter)),
                    inboxView: AnyView(inboxRoot), meView: AnyView(Text("Me")),
                    routeView: { route, router in
                        AnyView(destination(route).environment(\.appRouter, router))
                    }
                )
            } else {
                NavigationStack(path: $router.path) {
                    searchRoot(router: router)
                        .navigationTitle(MoroL10n.Search.exploreTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("切换测试账号") {
                                    accountKey = accountKey == "ui-search-a" ? "ui-search-b" : "ui-search-a"
                                }
                                .accessibilityIdentifier("search.switchAccount")
                            }
                        }
                        .navigationDestination(for: Route.self) { route in
                            destination(route).environment(\.appRouter, router)
                        }
                }
            }
        }
    }

    @ViewBuilder private var inboxRoot: some View {
        if testsAnimatedAvatars {
            AnimatedListAvatarHarnessRoot(tabs: tabs, autoplay: $autoplayAvatars,
                apiClient: client, accountKey: accountKey, theme: theme, tab: .inbox)
                .environmentObject(appState)
        } else { Text("Inbox") }
    }

    private var theme: MoroTheme {
        // Native roots are created once, before the parent hosting trait may settle.
        let color: ColorScheme = ProcessInfo.processInfo.environment["UITEST_COLOR_SCHEME"] == "dark" ? .dark : .light
        return MoroTheme(colorScheme: color, dynamicTypeSize: dynamicTypeSize)
    }

    @ViewBuilder private func searchRoot(router: AppRouter) -> some View {
        if testsAnimatedAvatars {
            AnimatedListAvatarHarnessRoot(tabs: tabs, autoplay: $autoplayAvatars,
                apiClient: client, accountKey: accountKey, theme: theme, tab: .explore)
                .environmentObject(appState)
        } else {
            SearchView(apiClient: client, onEntryStateChanged: tabs.setExploreSearchEntryActive)
                .environment(\.activeAccountKey, accountKey)
                .environment(\.appRouter, router)
                .environmentObject(appState)
                .moroTheme(theme)
        }
    }

    private func destination(_ route: Route) -> some View {
        AppRouteViewFactory(apiClient: client, appState: appState, cacheManager: .shared)
            .view(for: route)
            .environment(\.activeAccountKey, accountKey)
            .environmentObject(appState)
            .moroTheme(theme)
    }

}

/// Observe settings and tab activity inside retained roots without replacing navigation stacks.
private struct AnimatedListAvatarHarnessRoot: View {
    @ObservedObject var tabs: RootTabCoordinator
    @Binding var autoplay: Bool
    let apiClient: MastodonAPI
    let accountKey: String
    let theme: MoroTheme
    let tab: MainTab

    var body: some View {
        Group {
            if tab == .inbox {
                NotificationsView(apiClient: apiClient, sessionID: "ui-list-avatars", presentation: .inbox,
                    isActive: tabs.selectedTab == .inbox && tabs.isAtRoot(.inbox))
            } else {
                SearchView(apiClient: apiClient, onEntryStateChanged: tabs.setExploreSearchEntryActive)
            }
        }
        .environment(\.appRouter, tabs.router(for: tab))
        .environment(\.activeAccountKey, accountKey)
        .environment(\.tabReselection, tabs.tabReselection)
        .environment(\.moroMediaPrefs, MoroMediaPreferences(autoplayGIFs: autoplay))
        .moroTheme(theme)
    }
}

private final class SearchFixtureToken: AuthTokenProvider {
    var authToken: String? { "fixture-token" }
}

final class SearchFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var observedRequests: [URLRequest] = []
    private var responseTask: Task<Void, Never>?

    @MainActor
    static func makeClient() -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(
            baseURL: URL(string: "https://search-fixture.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: SearchFixtureToken())
        )
    }

    static var requests: [URLRequest] { lock.withLock { observedRequests } }
    static func resetRequests() { lock.withLock { observedRequests = [] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.observedRequests.append(request) }
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
        let type = components?.queryItems?.first(where: { $0.name == "type" })?.value
        responseTask = Task {
            do {
                if query == "slow" { try await Task.sleep(for: .milliseconds(250)) }
                try Task.checkCancellation()
                var account: [String: Any] = [
                    "id": "fixture-author", "username": "moro", "acct": "moro", "display_name": query.isEmpty ? "推荐账号" : "Result \(query)",
                    "note": "", "avatar": "", "avatar_static": "", "header": "", "header_static": "",
                    "followers_count": 10, "following_count": 5, "statuses_count": 1,
                ]
                if ProcessInfo.processInfo.environment["UITEST_ANIMATED_LIST_AVATARS"] == "1" {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TimelineMediaFixture", isDirectory: true)
                    account["avatar"] = directory.appendingPathComponent("avatar.gif").absoluteString
                    account["avatar_static"] = directory.appendingPathComponent("still.png").absoluteString
                }
                let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
                let limit = Int(components?.queryItems?.first(where: { $0.name == "limit" })?.value ?? "20") ?? 20
                let start = max(0, min(offset, 50))
                let resultAccounts = query == "long"
                    ? (start..<min(start + max(limit, 0), 50)).map { index -> [String: Any] in
                        var row = account
                        row["id"] = "fixture-author-\(index)"
                        row["display_name"] = "Result long \(index)"
                        return row
                    } : [account]
                let tag: [String: Any] = ["name": query.isEmpty ? "Moro" : query, "url": "https://search-fixture.invalid/tags/moro"]
                let poll: [String: Any] = [
                    "id": "fixture-poll", "expired": false, "multiple": false, "votes_count": 1,
                    "voted": url.path.hasSuffix("/votes"), "own_votes": url.path.hasSuffix("/votes") ? [0] : [],
                    "options": [["title": "One", "votes_count": 1], ["title": "Two", "votes_count": 0]],
                ]
                var post: [String: Any] = [
                    "id": "fixture-post", "content": "<p>结果 \(query)</p><p>阅读 <a href='https://example.com/a/very/long/path?first=1&amp;second=2'><span class='invisible'>https://</span>example.com/a…</a></p><pre><code>let value = &lt;limit&gt;\n  print(value)</code></pre>",
                    "created_at": "2026-09-05T10:00:00.000Z", "account": account,
                    "media_attachments": [], "favourites_count": 0, "reblogs_count": 0, "replies_count": 0,
                    "visibility": "public", "sensitive": false, "spoiler_text": "",
                ]
                if query == "poll" { post["poll"] = poll }
                if url.path.hasSuffix("/favourite") { post["favourited"] = true; post["favourites_count"] = 1 }
                if url.path.hasSuffix("/bookmark") { post["bookmarked"] = true }
                let payload: Any
                if url.path == "/api/v1/notifications" {
                    payload = (0..<24).map { index -> [String: Any] in
                        var actor = account
                        actor["id"] = "notification-actor-\(index)"
                        actor["display_name"] = "Actor \(index)"
                        var item: [String: Any] = ["id": String(1000 - index),
                            "type": index < 3 ? "favourite" : "follow", "created_at": "2026-10-30T01:00:00Z", "account": actor]
                        if index < 3 { item["status"] = post; item["group_key"] = "avatar-fixture-group" }
                        return item
                    }
                } else if url.path.hasSuffix("/votes") {
                    try await Task.sleep(for: .milliseconds(100))
                    payload = poll
                } else if url.path.hasSuffix("/search") {
                    payload = query == "empty" ? ["accounts": [], "statuses": [], "hashtags": []] : [
                        "accounts": type == nil || type == "accounts" ? resultAccounts : [],
                        "statuses": type == nil || type == "statuses" ? [post] : [],
                        "hashtags": type == nil || type == "hashtags" ? [tag] : [],
                    ]
                } else if url.path.hasSuffix("/directory") {
                    payload = [account]
                } else if url.path.hasSuffix("/trends/tags") {
                    payload = [tag]
                } else if url.path.hasSuffix("/trends/statuses") {
                    payload = [post]
                } else if url.path.hasSuffix("/relationships") {
                    payload = []
                } else if url.path.contains("/accounts/"), !url.path.hasSuffix("/statuses"), !url.path.hasSuffix("/featured_tags") {
                    payload = account
                } else if url.path.hasSuffix("/context") {
                    payload = ["ancestors": [], "descendants": []]
                } else if url.path.contains("/statuses/fixture-post") {
                    payload = post
                } else {
                    payload = []
                }
                let data = try JSONSerialization.data(withJSONObject: query == "error" ? ["error": "Fixture failure"] : payload)
                let response = HTTPURLResponse(url: url, statusCode: query == "error" ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                if !Task.isCancelled { client?.urlProtocol(self, didFailWithError: error) }
            }
        }
    }

    override func stopLoading() { responseTask?.cancel() }
}
#endif
