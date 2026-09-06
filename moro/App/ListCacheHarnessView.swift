#if DEBUG
import SwiftUI

struct ListCacheHarnessView: View {
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var prepared = false
    private let client: MastodonClient
    private let accountKey: String

    init() {
        let environment = ProcessInfo.processInfo.environment
        accountKey = "list-cache-ui-\(environment["UITEST_COLOR_SCHEME"] ?? "light")"
        ListCacheFixtureProtocol.reset(offline: environment["UITEST_LIST_OFFLINE"] == "1")
        client = ListCacheFixtureProtocol.makeClient()
    }

    var body: some View {
        NavigationStack {
            Group {
                if prepared {
                    List {
                        ForEach(["alpha", "beta"], id: \.self) { id in
                            NavigationLink {
                                ListTimelineView(list: MastodonList(id: id, title: id == "alpha" ? "甲列表" : "乙列表",
                                    repliesPolicy: nil, exclusive: nil), apiClient: client, cacheClientID: accountKey)
                            } label: { Text(id == "alpha" ? "甲列表" : "乙列表") }
                            .accessibilityIdentifier("listCache.open.\(id)")
                        }
                    }
                } else { ProgressView() }
            }
            .navigationTitle("测试列表")
            .task {
                guard !prepared else { return }
                if ProcessInfo.processInfo.environment["UITEST_LIST_RESET"] == "1" {
                    await CacheManager.shared.timelineCache.clearCache(for: accountKey)
                }
                prepared = true
            }
        }
        .environment(\.appRouter, router)
        .environmentObject(appState)
        .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
    }
}

final class ListCacheFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var payloads: [String: Data] = [:]
    private static var offline = false
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.withLock { recorded } }

    @MainActor static func reset(offline: Bool = false) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data: [String: Data] = [:]
        for (id, name) in [("alpha", "甲"), ("beta", "乙")] {
            let status = ThreadReadingFixtures.status("\(id)-new", content: "<p>\(name)列表独立正文</p>")
            data["/api/v1/timelines/list/\(id)"] = try! encoder.encode([status])
        }
        lock.withLock { payloads = data; Self.offline = offline; recorded = [] }
    }

    @MainActor static func makeClient() -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://list-cache-fixture.invalid")!,
            session: URLSession(configuration: configuration), authInterceptor: AuthInterceptor(tokenProvider: ListCacheFixtureToken()))
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data: Data? = Self.lock.withLock {
            Self.recorded.append(request)
            if Self.offline { return nil }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if query.contains(where: { $0.name == "max_id" }) { return Data("[]".utf8) }
            return Self.payloads[request.url!.path] ?? Data("[]".utf8)
        }
        guard let data else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class ListCacheFixtureToken: AuthTokenProvider { var authToken: String? { "list-cache-fixture" } }
#endif
