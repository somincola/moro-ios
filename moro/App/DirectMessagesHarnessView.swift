#if DEBUG
import SwiftUI

/// Exercises production conversations inside the same UIKit shell as the app.
/// Every API request stays in an ephemeral fixture transport.
struct DirectMessagesHarnessView: View {
    @StateObject private var tabs = RootTabCoordinator(selectedTab: .inbox)
    @StateObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let client = DirectMessagesFixtureProtocol.makeClient()

    init() {
        let state = AppState()
        state.currentAccount = try! JSONDecoder().decode(
            Account.self,
            from: JSONSerialization.data(withJSONObject: DirectMessagesFixtureProtocol.account("me"))
        )
        _appState = StateObject(wrappedValue: state)
    }

    var body: some View {
        MainShellContainerRepresentable(
            coordinator: tabs, theme: theme, unreadInboxCount: 0,
            currentUserAvatarURL: nil, contentVersion: "dm-fixture",
            homeView: AnyView(Text("Home")), exploreView: AnyView(Text("Explore")),
            inboxView: AnyView(
                DirectMessagesView(apiClient: client, showsDismissButton: false)
                    .environment(\.appRouter, tabs.inboxRouter)
                    .environmentObject(appState)
                    .moroTheme(theme)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
            ),
            meView: AnyView(Text("Me")),
            routeView: { route, router in
                AnyView(
                    AppRouteViewFactory(apiClient: client, appState: appState, cacheManager: .shared)
                        .view(for: route)
                        .environment(\.appRouter, router)
                        .environmentObject(appState)
                        .moroTheme(theme)
                        .environment(\.dynamicTypeSize, dynamicTypeSize)
                )
            }
        )
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .environmentObject(appState)
        .moroTheme(theme)
    }

    private var theme: MoroTheme {
        let color: ColorScheme = ProcessInfo.processInfo.environment["UITEST_COLOR_SCHEME"] == "dark" ? .dark : .light
        return MoroTheme(colorScheme: color, dynamicTypeSize: dynamicTypeSize)
    }
}

private final class DirectMessagesFixtureToken: AuthTokenProvider {
    var authToken: String? { "fixture-token" }
}

final class DirectMessagesFixtureProtocol: URLProtocol, @unchecked Sendable {
    @MainActor
    static func makeClient() -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(
            baseURL: URL(string: "https://dm-fixture.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: DirectMessagesFixtureToken())
        )
    }

    static func account(_ name: String) -> [String: Any] {
        ["id": "dm-\(name)", "username": name, "acct": "\(name)@dm-fixture.invalid",
         "display_name": name.capitalized, "note": "", "avatar": "", "avatar_static": "",
         "header": "", "header_static": "", "followers_count": 0, "following_count": 0, "statuses_count": 1]
    }

    static func status(_ id: String, author: String, content: String, replyTo: String? = nil, cardTitle: String? = nil) -> [String: Any] {
        var result: [String: Any] = [
            "id": id, "content": content, "created_at": "2026-09-08T01:00:00.000Z",
            "account": account(author), "media_attachments": [], "favourites_count": 0,
            "reblogs_count": 0, "replies_count": 0, "visibility": "direct", "sensitive": false, "spoiler_text": "",
        ]
        if let replyTo { result["in_reply_to_id"] = replyTo; result["created_at"] = "2026-09-08T01:01:00.000Z" }
        if let cardTitle {
            result["card"] = ["url": "https://remote.example/@author/123456789", "title": cardTitle,
                              "description": "An article shared in a direct message.", "type": "link"]
        }
        return result
    }

    static var root: [String: Any] {
        status("dm-root", author: "alice", content: """
            <p>A shared link</p><p><a href="https://remote.example/@author/123456789"><span class="invisible">https://</span><span class="ellipsis">remote.example/@author/123</span><span class="invisible">456789</span></a></p><p>Second paragraph<br>Another line</p>
            """, cardTitle: "Shared article")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = request.url!
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "q" }?.value ?? ""
            let payload: Any
            if url.path.hasSuffix("/conversations") {
                payload = ["alice", "bob", "eve", "dana", "frank"].map { name -> [String: Any] in
                    ["id": "dm-\(name)", "unread": false, "accounts": [Self.account(name)],
                     "last_status": name == "alice" ? Self.root : Self.status("dm-\(name)-root", author: name, content: "<p>Hello</p>")]
                }
            } else if url.path.hasSuffix("/context") {
                payload = ["ancestors": [], "descendants": []]
            } else if url.path.hasSuffix("/search") {
                if query.hasPrefix("https://") {
                    var remote = Self.status("resolved-remote", author: "author", content: "<p>Resolved remote article</p>")
                    remote["visibility"] = "public"
                    payload = ["accounts": [], "hashtags": [], "statuses": [remote]]
                } else {
                    payload = ["accounts": query == "empty" ? [] : [Self.account("charlie")], "statuses": [], "hashtags": []]
                }
            } else if url.path.hasSuffix("/statuses"), request.httpMethod == "POST" {
                payload = Self.status("dm-sent", author: "me", content: "<p>Sent in fixture</p>", replyTo: "dm-root", cardTitle: "Follow-up article")
            } else if url.path.contains("/statuses/resolved-remote") {
                var remote = Self.status("resolved-remote", author: "author", content: "<p>Resolved remote article</p>")
                remote["visibility"] = "public"
                payload = remote
            } else { payload = [] }
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}
#endif
