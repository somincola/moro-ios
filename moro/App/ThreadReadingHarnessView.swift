#if DEBUG
import SwiftUI

@MainActor enum ThreadReadingFixtures {
    static let author = Account(id: "author", username: "moro", acct: "moro", displayName: "Moro",
        note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
        followersCount: 0, followingCount: 0, statusesCount: 10)
    static let other = Account(id: "other", username: "reader", acct: "reader", displayName: "Reader",
        note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
        followersCount: 0, followingCount: 0, statusesCount: 10)

    static func status(_ id: String, parent: String? = nil, own: Bool = true, content: String? = nil) -> Status {
        Status(id: id, content: content ?? "<p>回复 \(id)</p>", createdAt: Date(timeIntervalSince1970: 1_788_631_200),
            account: own ? author : other, mediaAttachments: [], favouritesCount: 0, reblogsCount: 0,
            repliesCount: 0, bookmarked: false, favourited: false, reblogged: false,
            inReplyToID: parent, inReplyToAccountID: parent == nil ? nil : author.id)
    }
    static var focus: Status {
        status("focus", parent: "parent", content: "<p>当前帖子：阅读完整讨论。</p><p>链接 <a href=\"https://example.com/full/path?one=1&amp;two=2\">https://example.com/full/path?one=1&amp;two=2</a></p><pre><code>let value = 1\nprint(value)</code></pre>")
    }
    static var context: StatusContext {
        StatusContext(ancestors: [status("parent", own: false)], descendants: [
            status("a", parent: "focus", own: false),
            status("a1", parent: "a"),
            status("a2", parent: "a1", own: false),
            status("b", parent: "focus"),
            status("orphan", parent: "missing", own: false),
        ])
    }
}

struct ThreadReadingHarnessView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let client = ThreadFixtureProtocol.makeClient()
    var body: some View {
        NavigationStack(path: $router.path) {
            StatusDetailView(status: ThreadReadingFixtures.focus, apiClient: client, threadCache: ThreadCache())
                .navigationDestination(for: Route.self) { route in
                    AppRouteViewFactory(apiClient: client, appState: appState, cacheManager: .shared).view(for: route)
                }
        }
        .environment(\.appRouter, router)
        .environmentObject(appState)
        .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
    }
}

private final class ThreadFixtureToken: AuthTokenProvider { var authToken: String? { "fixture" } }

final class ThreadFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var payloads: [String: Data] = [:]

    @MainActor static func makeClient() -> MastodonClient {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let context = ThreadReadingFixtures.context
        let all = context.ancestors + [ThreadReadingFixtures.focus] + context.descendants
        var prepared: [String: Data] = [:]
        for status in all {
            prepared["/api/v1/statuses/\(status.id)"] = try! encoder.encode(status)
            prepared["/api/v1/statuses/\(status.id)/context"] = try! encoder.encode(
                status.id == "focus" ? context : StatusContext(ancestors: [], descendants: []))
        }
        lock.withLock { payloads = prepared }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://thread-fixture.invalid")!,
            session: URLSession(configuration: configuration), authInterceptor: AuthInterceptor(tokenProvider: ThreadFixtureToken()))
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.lock.withLock { Self.payloads[request.url!.path] ?? Data("[]".utf8) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
