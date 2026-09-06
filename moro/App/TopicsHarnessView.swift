#if DEBUG
import SwiftUI

struct TopicsHarnessView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var account = "a"
    @State private var timeline = TimelineType.home

    private static let seed: Void = { TopicFixtureProtocol.reset(failures: ["/api/v1/tags/Moro/follow": 1]) }()
    init() { _ = Self.seed }

    var body: some View {
        NavigationStack(path: $router.path) {
            VStack(spacing: 24) {
                TimelineSwitcher(selectedTimeline: $timeline, onManageLists: {}, onManageTopics: {
                    router.navigate(to: .followedTopics)
                })
                .accessibilityIdentifier("topics.homeMenu")
                Button("#Moro") { router.navigate(to: .hashtag("Moro")) }
                    .accessibilityIdentifier("topics.openMoro")
                Button("切换测试账号") { account = account == "a" ? "b" : "a" }
                    .accessibilityIdentifier("topics.switchAccount")
            }
            .navigationTitle("首页")
            .navigationDestination(for: Route.self) { route in
                AppRouteViewFactory(apiClient: TopicFixtureProtocol.makeClient(account: account), appState: appState, cacheManager: .shared)
                    .view(for: route)
            }
        }
        .environment(\.activeAccountKey, "ui-topic-\(account)")
        .environment(\.appRouter, router)
        .environmentObject(appState)
        .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
    }
}

private final class TopicFixtureToken: AuthTokenProvider {
    let authToken: String?
    init(_ account: String) { authToken = account }
}

final class TopicFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var followed: [String: Set<String>] = [:]
    private static var failures: [String: Int] = [:]
    private static var observed: [URLRequest] = []
    private static var sendsNextLink = true
    private static var repeatsCursor = false
    private var responseTask: Task<Void, Never>?

    static var requests: [URLRequest] { lock.withLock { observed } }
    static func failNext(_ path: String) { lock.withLock { failures[path] = 1 } }

    static func reset(failures: [String: Int] = [:], sendsNextLink: Bool = true, repeatsCursor: Bool = false) {
        lock.withLock {
            followed = ["a": ["Swift", "Rust"], "b": ["Other"]]
            Self.failures = failures
            observed = []
            Self.sendsNextLink = sendsNextLink
            Self.repeatsCursor = repeatsCursor
        }
    }

    @MainActor static func makeClient(account: String = "a") -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://topics-fixture.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: TopicFixtureToken(account)))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        responseTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(100))
                try Task.checkCancellation()
                let (code, body, headers) = Self.response(for: request)
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
                client?.urlProtocolDidFinishLoading(self)
            } catch { }
        }
    }
    override func stopLoading() { responseTask?.cancel() }

    private static func response(for request: URLRequest) -> (Int, Any, [String: String]) {
        lock.withLock {
            observed.append(request)
            let url = request.url!
            let path = url.path
            let account = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? "a"
            if (failures[path] ?? 0) > 0 {
                failures[path, default: 0] -= 1
                return (503, ["error": "Fixture retry"], [:])
            }
            func tag(_ name: String) -> [String: Any] {
                ["id": "tag-\(name)", "name": name, "url": "https://topics-fixture.invalid/tags/\(name)",
                 "history": [], "following": followed[account, default: []].contains(name)]
            }
            if path == "/api/v1/followed_tags" {
                let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "max_id" })?.value
                let names = followed[account, default: []].sorted()
                let offset = cursor == nil ? 0 : 2
                let page = names.dropFirst(offset).prefix(2).map(tag)
                let hasNext = names.count > offset + 2 || (cursor != nil && repeatsCursor)
                let headers = sendsNextLink && hasNext
                    ? ["Link": "<https://topics-fixture.invalid/api/v1/followed_tags?limit=2&max_id=relationship%3A2>; rel=\"next\""] : [:]
                return (200, page, headers)
            }
            if path.hasPrefix("/api/v1/tags/") {
                let name = String(path.split(separator: "/")[3])
                if path.hasSuffix("/unfollow") { followed[account, default: []].remove(name) }
                else if path.hasSuffix("/follow") { followed[account, default: []].insert(name) }
                return (200, tag(name), [:])
            }
            return (200, [], [:])
        }
    }
}
#endif
