#if DEBUG
import SwiftUI

struct BookmarksHarnessView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let client: MastodonClient
    private let library: BookmarkLibraryStore

    init() {
        let environment = ProcessInfo.processInfo.environment
        let name = "bookmarks-ui-\(environment["UITEST_COLOR_SCHEME"] ?? "light")"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let defaults = UserDefaults(suiteName: name)!
        if environment["UITEST_BOOKMARK_RESET"] == "1" {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: name)
        }
        BookmarkFixtureProtocol.reset(offline: environment["UITEST_BOOKMARK_OFFLINE"] == "1",
                                      failures: ["/api/v1/statuses/b2/unbookmark": 1])
        client = BookmarkFixtureProtocol.makeClient()
        library = BookmarkLibraryStore(accountKey: "bookmark-fixture:a", directory: directory, defaults: defaults)
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            BookmarksView(apiClient: client, library: library)
                .navigationDestination(for: Route.self) { route in
                    AppRouteViewFactory(apiClient: client, appState: appState, cacheManager: .shared).view(for: route)
                }
        }
        .environment(\.appRouter, router)
        .environmentObject(appState)
        .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
    }
}

final class BookmarkFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var payloads: [String: Data] = [:]
    private static var failures: [String: Int] = [:]
    private static var offline = false
    private static var sendsNextLink = true
    private static var repeatsCursor = false
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.withLock { recorded } }

    @MainActor static var statuses: [Status] {
        [ThreadReadingFixtures.status("b1", content: "<p>完整链接书签 <a href=\"https://example.com/hidden?secret=1\">点击阅读</a></p>"),
         ThreadReadingFixtures.status("b2", content: "<p>旅行笔记：周末去海边</p>"),
         ThreadReadingFixtures.status("b3", content: "<p>更多书签：第三篇文章</p>")].map { $0.updating(bookmarked: true) }
    }

    @MainActor static func reset(offline: Bool = false, failures: [String: Int] = [:],
                                sendsNextLink: Bool = true, repeatsCursor: Bool = false) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let statuses = statuses
        var data: [String: Data] = ["first": try! encoder.encode(Array(statuses.prefix(2))),
                                    "next": try! encoder.encode([statuses[1], statuses[2], statuses[2]])]
        for status in statuses {
            data["/api/v1/statuses/\(status.id)"] = try! encoder.encode(status)
            data["/api/v1/statuses/\(status.id)/unbookmark"] = try! encoder.encode(status.updating(bookmarked: false))
            data["/api/v1/statuses/\(status.id)/context"] = try! encoder.encode(StatusContext(ancestors: [], descendants: []))
        }
        lock.withLock {
            payloads = data; Self.offline = offline; Self.failures = failures
            Self.sendsNextLink = sendsNextLink; Self.repeatsCursor = repeatsCursor; recorded = []
        }
    }

    static func failNext(_ path: String) { lock.withLock { failures[path, default: 0] += 1 } }

    @MainActor static func makeClient() -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://bookmark-fixture.invalid")!,
            session: URLSession(configuration: configuration), authInterceptor: AuthInterceptor(tokenProvider: BookmarkFixtureToken()))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply: (Int, Data, [String: String])? = Self.lock.withLock {
            Self.recorded.append(request)
            guard !Self.offline else { return nil }
            let url = request.url!
            if Self.failures[url.path, default: 0] > 0 {
                Self.failures[url.path, default: 0] -= 1
                return (503, Data("{\"error\":\"fixture failure\"}".utf8), [:])
            }
            if url.path == "/api/v1/bookmarks" {
                let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "max_id" }?.value
                let headers = Self.sendsNextLink && (cursor == nil || Self.repeatsCursor)
                    ? ["Link": "<https://bookmark-fixture.invalid/api/v1/bookmarks?max_id=bookmark%3Acursor>; rel=\"next\""] : [:]
                return (200, Self.payloads[cursor == nil ? "first" : "next"]!, headers)
            }
            return (200, Self.payloads[url.path] ?? Data("[]".utf8), [:])
        }
        guard let reply else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.0,
            httpVersion: nil, headerFields: reply.2)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BookmarkFixtureToken: AuthTokenProvider { var authToken: String? { "bookmark-fixture" } }
#endif
