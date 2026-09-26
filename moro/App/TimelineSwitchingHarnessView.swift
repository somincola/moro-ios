#if DEBUG
import Combine
import SwiftUI

/// Exercises the real tab coordinator, retained pager, refresh gestures and REST
/// pagination together. Every source has distinct IDs and an isolated cache scope.
struct TimelineSwitchingHarnessView: View {
    @StateObject private var appState = AppState()
    @ObservedObject private var fixture = TimelineSwitchingFixtureProtocol.state
    @State private var sessionID = "timeline-switch-\(UUID().uuidString)"
    private let client = TimelineSwitchingFixtureProtocol.makeClient()

    var body: some View {
        MainTabView(apiClient: client, onLogout: {}, accountSessions: [],
            activeSessionID: sessionID, onSwitchAccount: { _ in },
            onRemoveAccount: { _ in }, onAccountAuthenticated: { _, _, _ in })
            .environmentObject(appState)
            .moroTheme(MoroTheme())
            .overlay(alignment: .bottom) {
                VStack(spacing: 2) {
                    HStack {
                        Button("新增") { fixture.addPosts() }
                            .accessibilityIdentifier("timeline.switch.add")
                        Button("延迟") { fixture.delayNext = true }
                            .accessibilityIdentifier("timeline.switch.delay")
                        Button("返回") { fixture.releaseRequests() }
                            .accessibilityIdentifier("timeline.switch.release")
                        Button("失败") { fixture.failNext = true }
                            .accessibilityIdentifier("timeline.switch.fail")
                    }
                    .buttonStyle(.bordered)
                    Text(fixture.requestSummary)
                        .font(.system(size: 8, design: .monospaced))
                        .accessibilityIdentifier("timeline.switch.requests")
                }
                .padding(4)
                .background(.regularMaterial)
                .padding(.bottom, 94)
            }
    }
}

@MainActor
final class TimelineSwitchingFixtureState: ObservableObject {
    @Published private(set) var requestSummary = "ready"
    private var lastRequests: [String: String] = [:]
    private var olderPages: [String: Int] = [:]
    private var heldRequests: [UUID: AsyncStream<Void>.Continuation] = [:]
    private(set) var latest = ["home": 60, "local": 60, "federated": 60]
    var delayNext = false
    var failNext = false

    func addPosts() {
        for source in ["home", "local", "federated"] { latest[source, default: 60] += 1 }
    }

    func record(_ message: String) {
        let source = String(message.prefix { $0 != ":" })
        lastRequests[source] = message
        requestSummary = lastRequests.keys.sorted().compactMap { key in
            lastRequests[key].map { "\($0),\(key):olderPages=\(olderPages[key, default: 0])" }
        }.joined(separator: "|")
    }

    func didServeOlderPage(for source: String) {
        olderPages[source, default: 0] += 1
    }

    /// A test-controlled response gate avoids depending on XCTest gesture timing.
    /// Task cancellation ends AsyncStream.next(), so cancelled transports do not leak.
    func waitForRelease() async {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        heldRequests[id] = continuation
        defer { heldRequests[id] = nil }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func releaseRequests() {
        failNext = false
        for continuation in heldRequests.values {
            continuation.yield(())
            continuation.finish()
        }
    }
}

final class TimelineSwitchingFixtureProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static let state = TimelineSwitchingFixtureState()
    private let taskLock = NSLock()
    private var loadingTask: Task<Void, Never>?

    @MainActor static func makeClient() -> MastodonClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://timeline-switch-fixture.invalid")!,
            session: URLSession(configuration: config),
            authInterceptor: AuthInterceptor(tokenProvider: TimelineSwitchingFixtureToken()))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let task = Task { @MainActor [weak self] in
            guard let self, let url = request.url else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data: Data
                var headers = ["Content-Type": "application/json"]
                if url.path.contains("/timelines/") {
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
                    let source = url.path.hasSuffix("/home") ? "home"
                        : (value("local") == "true" || value("local") == "1" ? "local" : "federated")
                    let base = source == "home" ? 1000 : (source == "local" ? 2000 : 3000)
                    let maxID = value("max_id").flatMap(Int.init)
                    let sinceID = value("since_id").flatMap(Int.init)
                    // A server cap plus an explicit Link exercises real cursor-based
                    // continuation even when the client asks for a larger page.
                    let limit = min(value("limit").flatMap(Int.init) ?? 20, 20)
                    let kind = maxID != nil ? "older" : (sinceID != nil ? "newer" : "initial")
                    let controlledSource = ProcessInfo.processInfo.environment["UITEST_TIMELINE_CONTROL_SOURCE"] ?? "home"
                    let controlled = source == controlledSource
                    let delayed = controlled && Self.state.delayNext
                    let failed = controlled && Self.state.failNext
                    if controlled {
                        Self.state.delayNext = false
                    }
                    Self.state.record("\(source):\(kind):started")
                    if delayed { await Self.state.waitForRelease() }
                    try Task.checkCancellation()
                    if failed {
                        Self.state.record("\(source):\(kind):failed")
                        throw URLError(.notConnectedToInternet)
                    }
                    let latest = base + Self.state.latest[source, default: 60]
                    let ids = ((base + 1)...latest).reversed().filter { id in
                        (maxID.map { id < $0 } ?? true) && (sinceID.map { id > $0 } ?? true)
                    }.prefix(limit)
                    let posts = ids.map {
                        ThreadReadingFixtures.status(String($0), own: false,
                            content: "<p>Switch \(source) \($0)</p><p>保留这条动态的阅读位置，切换后应继续正常加载。</p>")
                    }
                    data = try encoder.encode(posts)
                    if sinceID == nil, let last = ids.last, last > base + 1 {
                        var next = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                        next.queryItems = query.filter { $0.name != "max_id" }
                            + [URLQueryItem(name: "max_id", value: String(last))]
                        headers["Link"] = "<\(next.url!.absoluteString)>; rel=\"next\""
                    }
                    if maxID != nil, !posts.isEmpty { Self.state.didServeOlderPage(for: source) }
                    Self.state.record("\(source):\(kind):\(posts.count):\(posts.last?.id ?? "end")")
                } else if url.path.hasSuffix("/verify_credentials") {
                    data = try encoder.encode(ThreadReadingFixtures.author)
                } else if url.path.hasSuffix("/markers") || url.path.hasSuffix("/preferences") {
                    data = Data("{}".utf8)
                } else {
                    data = Data("[]".utf8)
                }
                try Task.checkCancellation()
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200,
                    httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch is CancellationError {
                // URLSession has already cancelled this request.
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        taskLock.withLock { loadingTask = task }
    }

    override func stopLoading() {
        taskLock.withLock {
            loadingTask?.cancel()
            loadingTask = nil
        }
    }
}

private final class TimelineSwitchingFixtureToken: AuthTokenProvider {
    var authToken: String? { "timeline-switch-fixture" }
}
#endif
