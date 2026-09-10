#if DEBUG
import Combine
import SwiftUI

/// Production composer and post card, backed by a server that can commit a post
/// and then lose the response. No request reaches a Mastodon server.
struct ComposePublishingHarnessView: View {
    @StateObject private var fixture = ComposePublishingFixtureState()
    @StateObject private var coordinator = RootTabCoordinator()

    var body: some View {
        VStack {
            Button("Compose") {
                coordinator.composeContext = ComposeContextWrapper(context: fixture.context, draft: fixture.draft)
            }
                .accessibilityIdentifier("publishFixture.open")
            if let status = fixture.publishedStatus {
                let counts = ComposePublishingFixtureProtocol.counts(for: fixture.client)
                Text("Published posts: \(counts.posts); requests: \(counts.requests)")
                    .accessibilityIdentifier("publishFixture.result")
                Text(coordinator.composeContext == nil ? "Presentation closed" : "Presentation open")
                    .accessibilityIdentifier("publishFixture.presentation")
                if fixture.isRefreshing {
                    Text("Refresh pending").accessibilityIdentifier("publishFixture.refresh")
                }
                ScrollView { PostCard(status: status) }
            }
        }
        .fullScreenCover(item: $coordinator.composeContext) { wrapper in
            ComposeView(context: wrapper.context, apiClient: fixture.client, currentUserID: "dm-publisher",
                draftStore: fixture.draftStore, initialDraft: wrapper.draft,
                onDismiss: {
                    fixture.dismissalRequested = true
                    if fixture.scenario == "delayed-dismiss" {
                        // Hold only the test presentation open to inspect the success/closing state.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            coordinator.composeContext = nil
                        }
                    } else {
                        coordinator.composeContext = nil
                    }
                }) { status in
                    fixture.publishedStatus = status
                    if fixture.scenario == "slow-refresh" {
                        fixture.isRefreshing = true
                        Task {
                            _ = try? await fixture.client.fetchStatusDetail(id: "refresh")
                            fixture.isRefreshing = false
                        }
                    }
                }
                .environmentObject(fixture.appState)
                .overlay(alignment: .top) {
                    if fixture.scenario == "delayed-dismiss", fixture.dismissalRequested {
                        Text("Dismissal requested").accessibilityIdentifier("publishFixture.dismissalRequested")
                    }
                }
        }
    }
}

@MainActor
private final class ComposePublishingFixtureState: ObservableObject {
    let appState: AppState
    let client: MastodonClient
    let draftStore = ComposeDraftStore(userDefaults: UserDefaults(suiteName: "ui-publishing-\(UUID().uuidString)")!)
    let draft: ComposeDraft
    let context: ComposeViewModel.ComposeContext
    let scenario = ProcessInfo.processInfo.environment["UITEST_PUBLISH_SCENARIO"] ?? "success"
    @Published var publishedStatus: Status?
    @Published var dismissalRequested = false
    @Published var isRefreshing = false

    init() {
        let appState = AppState()
        let client = ComposePublishingFixtureProtocol.makeClient()
        self.appState = appState
        self.client = client
        let author = Account(id: "dm-publisher", username: "publisher", acct: "publisher", displayName: "Publisher",
            note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "", followersCount: 0, followingCount: 0, statusesCount: 0)
        appState.currentAccount = author
        let original = Status(id: "original", content: "<p>Original post</p>", createdAt: Date(), account: author,
            mediaAttachments: [], favouritesCount: 0, reblogsCount: 0, repliesCount: 0, bookmarked: false,
            favourited: false, reblogged: false, inReplyToID: nil, mentions: [], filtered: nil)
        let context: ComposeViewModel.ComposeContext = scenario.contains("reply") ? .reply(to: original) : .newPost
        self.context = context
        let model = ComposeViewModel(context: context, apiClient: client, currentUserID: author.id)
        model.content = "Publish once :cat:\n\n" + String(repeating: "长文测试，文字应该立即出现，发布只需要一次。😀\n", count: 130)
        model.visibility = .public
        draft = model.makeDraft(category: .manual)
    }
}

private final class ComposePublishingFixtureToken: AuthTokenProvider {
    var authToken: String? { "publishing-fixture-token" }
}

final class ComposePublishingFixtureProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var posts: [String: Data] = [:]
        var requests = 0
    }
    private static let lock = NSLock()
    private static var states: [String: State] = [:]
    private var delivery: Task<Void, Never>?

    @MainActor static func makeClient() -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://\(UUID().uuidString).publishing-fixture.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: ComposePublishingFixtureToken()))
    }

    @MainActor static func counts(for client: MastodonClient) -> (posts: Int, requests: Int) {
        lock.withLock {
            let state = states[URL(string: client.instanceMetadataCacheKey!)!.host!]
            return (state?.posts.count ?? 0, state?.requests ?? 0)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { delivery?.cancel() }

    override func startLoading() {
        do {
            let url = request.url!
            var data: Data
            var losesResponse = false
            if url.path == "/api/v1/statuses", request.httpMethod == "POST" {
                let body = try JSONSerialization.jsonObject(with: requestBody()) as? [String: Any]
                let text = body?["status"] as? String ?? ""
                let html = "<p>" + text.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br>") + "</p>"
                var status = DirectMessagesFixtureProtocol.status("published-once", author: "publisher", content: html)
                status["visibility"] = body?["visibility"] ?? "public"
                status["in_reply_to_id"] = body?["in_reply_to_id"]
                status["emojis"] = [["shortcode": "cat", "url": "https://emoji-fixture.invalid/cat.png",
                    "static_url": "https://emoji-fixture.invalid/cat.png"]]
                let candidate = try JSONSerialization.data(withJSONObject: status)
                // A missing header deliberately creates a new server record on every retry.
                let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? UUID().uuidString
                data = Self.lock.withLock {
                    var state = Self.states[url.host!] ?? State()
                    state.requests += 1
                    let stored = state.posts[key] ?? candidate
                    state.posts[key] = stored
                    losesResponse = ProcessInfo.processInfo.environment["UITEST_PUBLISH_SCENARIO"] == "lost-response" && state.requests == 1
                    Self.states[url.host!] = state
                    return stored
                }
            } else if url.path == "/api/v1/statuses/refresh" {
                data = try JSONSerialization.data(withJSONObject: DirectMessagesFixtureProtocol.root)
            } else if url.path.contains("/instance") {
                data = try JSONSerialization.data(withJSONObject: ["uri": url.host!, "domain": url.host!,
                    "title": "Publishing fixture", "description": "", "version": "4.5.0",
                    "configuration": ["statuses": ["max_characters": 5_000]]])
            } else {
                data = Data("[]".utf8)
            }
            let result = data
            let fail = losesResponse
            delivery = Task {
                let scenario = ProcessInfo.processInfo.environment["UITEST_PUBLISH_SCENARIO"]
                let delay: UInt64
                if url.path == "/api/v1/statuses/refresh" {
                    delay = 15_000_000_000
                } else if self.request.httpMethod == "POST" {
                    delay = scenario == "slow-post" || scenario == "slow-reply" ? 8_000_000_000
                        : scenario == "immediate" ? 0 : 600_000_000
                } else {
                    delay = 0
                }
                if delay > 0 {
                    do { try await Task.sleep(nanoseconds: delay) } catch { return }
                }
                guard !Task.isCancelled else { return }
                if fail {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                } else {
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    self.client?.urlProtocol(self, didLoad: result)
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    private func requestBody() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
#endif
