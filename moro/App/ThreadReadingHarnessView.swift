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
            inReplyToID: parent, inReplyToAccountID: parent == nil ? nil : author.id, visibility: "public")
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

private enum EngagementFixtures {
    static let favourites = [
        account("yuki", "小雪"), account("rei", "阿澪"), account("lin", "林间"),
        account("kai", "Kai"), account("mira", "Mira"),
    ]
    static let boosts = [account("sora", "空山"), account("moss", "Moss")]

    static func readers(_ count: Int) -> [Account] {
        let extra = (0..<max(0, count - favourites.count)).map { index in
            account("fern-\(index)", "园友 \(index + 1)")
        }
        return Array((favourites + extra).prefix(count))
    }

    static func post(_ mode: String) -> Status {
        let post = ThreadReadingFixtures.status("garden-walk", content: "<p>周末去植物园散步，温室里的龟背竹又长出了一片新叶。</p>")
        if mode == "partial" {
            return post.updating(favouritesCount: 24, reblogsCount: 6, repliesCount: 1)
        }
        return post.updating(favouritesCount: mode == "long" ? 24 : (mode == "both" ? favourites.count : 0),
                             reblogsCount: mode == "none" ? 0 : boosts.count, repliesCount: 1)
    }

    private static func account(_ name: String, _ displayName: String) -> Account {
        Account(id: name, username: name, acct: "\(name)@garden.example", displayName: displayName,
                note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
                followersCount: 12, followingCount: 16, statusesCount: 0)
    }
}

struct ThreadReadingHarnessView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let focusedStatus: Status
    private let client: MastodonClient

    init() {
        let useSample = ProcessInfo.processInfo.arguments.contains("UITEST_THREAD_REAL_SAMPLE")
        let context: StatusContext
        if let mode = ProcessInfo.processInfo.environment["UITEST_POST_INTERACTIONS"] {
            focusedStatus = EngagementFixtures.post(mode)
            context = StatusContext(ancestors: [], descendants: [ThreadReadingFixtures.status(
                "garden-reply", parent: focusedStatus.id, own: false, content: "<p>我也喜欢这间温室！</p>")])
        } else {
            focusedStatus = useSample ? ThreadReadingSample.focus : ThreadReadingFixtures.focus
            context = useSample ? ThreadReadingSample.context : ThreadReadingFixtures.controlsContext
        }
        client = ThreadFixtureProtocol.makeClient(focus: focusedStatus, context: context)
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
        .moroTheme(MoroTheme(colorScheme: colorScheme, postFontSize: settings.postFontSize, dynamicTypeSize: dynamicTypeSize))
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
            prepared["/api/v1/statuses/\(status.id)/reblog"] = try! encoder.encode(
                status.updating(reblogsCount: status.reblogsCount + 1, reblogged: true))
            prepared["/api/v1/statuses/\(status.id)/unreblog"] = try! encoder.encode(status)
            prepared["/api/v1/statuses/\(status.id)/context"] = try! encoder.encode(
                status.id == focus.id ? context : StatusContext(ancestors: ancestors.reversed(), descendants: descendants))
        }
        if focus.id == "garden-walk" {
            let prefix = "/api/v1/statuses/\(focus.id)"
            let partial = ProcessInfo.processInfo.environment["UITEST_POST_INTERACTIONS"] == "partial"
            let likes = EngagementFixtures.readers(partial ? 1 : focus.favouritesCount)
            let boosts = !partial && focus.reblogsCount > 0 ? EngagementFixtures.boosts : []
            prepared[prefix + "/favourited_by"] = try! encoder.encode(Array(likes.prefix(2)))
            if likes.count > 2 {
                prepared[prefix + "/favourited_by?max_id=relation-7"] = try! encoder.encode(Array(likes.dropFirst(2)))
            }
            prepared[prefix + "/reblogged_by"] = try! encoder.encode(boosts)
            for account in likes + boosts {
                prepared["/api/v1/accounts/\(account.id)"] = try! encoder.encode(account)
            }
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
        let url = request.url!
        let (data, headers): (Data, [String: String]) = Self.lock.withLock {
            let firstPage = Self.payloads[url.path] ?? Data("[]".utf8)
            let next = url.path + "?max_id=relation-7"
            if let nextPage = Self.payloads[next] {
                if url.query == "max_id=relation-7" { return (nextPage, [:]) }
                return (firstPage, ["Link": "<" + next + ">; rel=\"next\""])
            }
            return (firstPage, [:])
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
