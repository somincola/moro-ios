#if DEBUG
import SwiftUI

/// Uses the production reply editor with local fixtures and an offline transport.
struct ComposeReplyHarnessView: View {
    @StateObject private var appState = AppState()
    @StateObject private var accountCache: AccountCache
    @State private var presentsReply = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let client: MastodonClient
    private let status: Status
    private let draft: ComposeDraft?
    private let isNewPost: Bool
    private let draftStore = ComposeDraftStore(userDefaults: UserDefaults(suiteName: "ui-compose-reply")!)

    init() {
        let mode = ProcessInfo.processInfo.environment["UITEST_REPLY_MODE"] ?? "mentions"
        isNewPost = mode == "new" || mode == "long"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplyFixtureProtocol.self]
        let client = MastodonClient(
            baseURL: URL(string: "https://\(UUID().uuidString.lowercased()).reply-fixture.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: ReplyFixtureTokenProvider())
        )
        self.client = client
        let cache = AccountCache()
        if mode == "cached" { cache.set(Self.account("alice")) }
        _accountCache = StateObject(wrappedValue: cache)
        let mentions = mode == "mentions" ? [Status.Mention(
            id: "alice", username: "alice", url: URL(string: "https://example.com/@alice")!, acct: "alice@example.com"
        )] : []
        let status = Status(
            id: "fixture-reply", content: "<p>A post in a conversation.</p>", createdAt: Date(),
            account: Self.account(mode == "original" ? "alice" : "bob"), mediaAttachments: [],
            favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
            bookmarked: false, favourited: false, reblogged: false,
            inReplyToID: mode == "original" ? nil : "status-alice",
            inReplyToAccountID: mode == "original" ? nil : "alice",
            mentions: mentions, filtered: nil
        )
        self.status = status
        if mode == "draft" || mode == "long" {
            let model = ComposeViewModel(context: isNewPost ? .newPost : .reply(to: status), apiClient: client,
                                         currentUserID: "me", accountCache: cache)
            model.content = mode == "long"
                ? (1...45).map { "Line \($0): A longer post with room to keep writing." }.joined(separator: "\n") + "\n"
                : "@bob@example.com 草稿 👋  \n"
            draft = model.makeDraft(category: .manual)
        } else {
            draft = nil
        }
    }

    var body: some View {
        VStack {
            Button("Reply") { presentsReply = true }
                .accessibilityIdentifier("replyHarness.open")
            Text("Recipient requests: \(ReplyFixtureProtocol.recipientRequestCount)")
                .accessibilityIdentifier("replyHarness.recipientRequests")
        }
        .fullScreenCover(isPresented: $presentsReply) {
            ComposeView(context: isNewPost ? .newPost : .reply(to: status), apiClient: client, currentUserID: "me",
                        draftStore: draftStore, initialDraft: draft, accountCache: accountCache)
                .environmentObject(appState)
                .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
        }
    }

    private static func account(_ id: String) -> Account {
        Account(id: id, username: id, acct: "\(id)@example.com", displayName: id.capitalized, note: "",
                avatar: "", avatarStatic: "", header: "", headerStatic: "",
                followersCount: 0, followingCount: 0, statusesCount: 1)
    }
}

private final class ReplyFixtureTokenProvider: AuthTokenProvider {
    var authToken: String? { "fixture-token" }
}

private final class ReplyFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var recipientRequests = 0
    static var recipientRequestCount: Int { lock.withLock { recipientRequests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        if path.hasPrefix("/api/v1/accounts/") || path.hasPrefix("/api/v1/statuses/") {
            Self.lock.withLock { Self.recipientRequests += 1 }
        }
        if path == "/api/v2/search", let url = request.url {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = items.first { $0.name == "q" }?.value ?? ""
            let type = items.first { $0.name == "type" }?.value
            let accounts = [
                account("hanna", acct: "hanna@remote.example", displayName: "Hanna"),
                account("hanna-garden", acct: "hanna@garden.example", displayName: "hanna🌱"),
                account("alex-hanna", acct: "alex@social.example", displayName: "Alex Hanna")
            ]
            let history = [2, 12, 7, 5, 5, 7, 13].enumerated().map { index, uses in
                SearchTagHistory(day: String(1_788_825_600 - index * 86_400), uses: String(uses), accounts: "2")
            }
            let tags = [
                SearchTag(name: "SwiftUI", url: URL(string: "https://example.com/tags/SwiftUI")!, history: history),
                SearchTag(name: "Movies", url: URL(string: "https://example.com/tags/Movies")!, history: history),
                SearchTag(name: "MovieNight", url: URL(string: "https://example.com/tags/MovieNight")!, history: nil),
                SearchTag(name: "MovieClub", url: URL(string: "https://example.com/tags/MovieClub")!, history: [SearchTagHistory(day: "1788825600", uses: "8", accounts: "3")]),
                SearchTag(name: "MovieChat", url: URL(string: "https://example.com/tags/MovieChat")!, history: [])
            ]
            let results = SearchResults(
                accounts: type == "accounts" ? accounts.filter {
                    $0.acct.localizedCaseInsensitiveContains(query) || $0.displayName.localizedCaseInsensitiveContains(query)
                } : [],
                hashtags: type == "hashtags" ? tags.filter { $0.name.localizedCaseInsensitiveContains(query) } : []
            )
            let data = try! JSONEncoder().encode(results)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}

    private func account(_ id: String, acct: String, displayName: String) -> Account {
        Account(id: id, username: String(acct.split(separator: "@")[0]), acct: acct, displayName: displayName,
                note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
                followersCount: 0, followingCount: 0, statusesCount: 1)
    }
}
#endif
