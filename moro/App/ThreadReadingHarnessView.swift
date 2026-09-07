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

    /// Exercise both sides of the disclosure threshold without changing the graph fixtures.
    static var controlsContext: StatusContext {
        let base = context
        return StatusContext(ancestors: base.ancestors, descendants: base.descendants + [
            status("a3", parent: "a2", own: false),
            status("short", parent: "focus", own: false),
            status("short1", parent: "short", own: false),
            status("short2", parent: "short1", own: false),
        ])
    }
}

struct ThreadReadingHarnessView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let focusedStatus: Status
    private let client: MastodonClient

    init() {
        let useSample = ProcessInfo.processInfo.arguments.contains("UITEST_THREAD_REAL_SAMPLE")
        focusedStatus = useSample ? ThreadReadingSample.focus : ThreadReadingFixtures.focus
        client = ThreadFixtureProtocol.makeClient(
            focus: focusedStatus,
            context: useSample ? ThreadReadingSample.context : ThreadReadingFixtures.controlsContext
        )
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            StatusDetailView(status: focusedStatus, apiClient: client, threadCache: ThreadCache())
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

    @MainActor static func makeClient(focus: Status, context: StatusContext) -> MastodonClient {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let all = context.ancestors + [focus] + context.descendants
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let children = Dictionary(grouping: all, by: { $0.inReplyToID ?? "" })
        var prepared: [String: Data] = [:]
        for status in all {
            var ancestors: [Status] = []
            var parentID = status.inReplyToID
            var seen: Set<String> = [status.id]
            while let id = parentID, let parent = byID[id], seen.insert(id).inserted {
                ancestors.append(parent)
                parentID = parent.inReplyToID
            }
            var descendants: [Status] = []
            var pending = Array((children[status.id] ?? []).reversed())
            while let reply = pending.popLast() {
                guard seen.insert(reply.id).inserted else { continue }
                descendants.append(reply)
                pending.append(contentsOf: (children[reply.id] ?? []).reversed())
            }
            prepared["/api/v1/statuses/\(status.id)"] = try! encoder.encode(status)
            prepared["/api/v1/statuses/\(status.id)/context"] = try! encoder.encode(
                status.id == focus.id ? context : StatusContext(ancestors: ancestors.reversed(), descendants: descendants))
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
