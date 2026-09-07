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

    init() {
        let mode = ProcessInfo.processInfo.environment["UITEST_REPLY_MODE"] ?? "mentions"
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
        if mode == "draft" {
            let model = ComposeViewModel(context: .reply(to: status), apiClient: client,
                                         currentUserID: "me", accountCache: cache)
            model.content = "@bob@example.com 草稿 👋  \n"
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
            ComposeView(context: .reply(to: status), apiClient: client, currentUserID: "me",
                        initialDraft: draft, accountCache: accountCache)
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
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
