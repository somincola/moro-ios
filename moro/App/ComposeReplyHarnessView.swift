#if DEBUG
import SwiftUI

/// Uses the production reply editor and an isolated, optionally delayed transport.
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
        if mode == "cached" { cache.cacheFromStatuses([Self.makeStatus(author: "alice", mentions: [])]) }
        _accountCache = StateObject(wrappedValue: cache)
        let mentions = mode == "mentions" ? [Status.Mention(
            id: "alice", username: "alice", url: URL(string: "https://example.com/@alice")!, acct: "alice@example.com"
        )] : []
        let status = Self.makeStatus(author: "bob", mentions: mentions)
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
        Button("Reply") { presentsReply = true }
            .accessibilityIdentifier("replyHarness.open")
            .fullScreenCover(isPresented: $presentsReply) {
                ComposeView(context: .reply(to: status), apiClient: client, currentUserID: "me",
                            initialDraft: draft, accountCache: accountCache)
                    .environmentObject(appState)
                    .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
            }
    }

    private static func makeStatus(author: String, mentions: [Status.Mention]) -> Status {
        Status(id: "status-\(author)", content: "<p>A reply in a conversation.</p>", createdAt: Date(),
               account: ReplyFixtureProtocol.account(author), mediaAttachments: [],
               favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
               bookmarked: false, favourited: false, reblogged: false,
               inReplyToID: "status-alice", inReplyToAccountID: "alice", mentions: mentions, filtered: nil)
    }
}

private final class ReplyFixtureTokenProvider: AuthTokenProvider {
    var authToken: String? { "fixture-token" }
}

private final class ReplyFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var accountRequests = 0
    private var responseTask: Task<Void, Never>?

    static func account(_ id: String) -> Account {
        Account(id: id, username: id, acct: "\(id)@example.com", displayName: id.capitalized, note: "",
                avatar: "", avatarStatic: "", header: "", headerStatic: "",
                followersCount: 0, followingCount: 0, statusesCount: 1)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isAccountRequest = request.url?.path == "/api/v1/accounts/alice"
        let attempt = Self.lock.withLock {
            if isAccountRequest { Self.accountRequests += 1 }
            return Self.accountRequests
        }
        let mode = ProcessInfo.processInfo.environment["UITEST_REPLY_MODE"] ?? "mentions"
        responseTask = Task {
            do {
                if isAccountRequest { try await Task.sleep(for: .seconds(3)) }
                try Task.checkCancellation()
                let succeeds = isAccountRequest && (mode == "delayed" || (mode == "retry" && attempt > 1))
                let data = succeeds ? try JSONEncoder().encode(Self.account("alice")) : Data("{\"error\":\"Fixture unavailable\"}".utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: succeeds ? 200 : 503,
                                               httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
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
