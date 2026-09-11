#if DEBUG
import SwiftUI

/// Uses the production pager, rows and native scroll bridge with an offline transport.
struct TimelineLiveHarnessView: View {
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter()
    @StateObject private var model: TimelineViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: TimelineType = .home
    @State private var nextID = 101
    @State private var covered = false
    private let client: MastodonClient
    private let key: String

    init() {
        let key = "timeline-live-ui-\(UUID().uuidString)"
        let client = TimelineLiveFixtureProtocol.makeClient()
        self.key = key
        self.client = client
        _model = StateObject(wrappedValue: TimelineViewModel(apiClient: client,
            accountCache: AccountCache(), feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(), cacheClientID: key, defersLivePresentation: true))
    }

    var body: some View {
        NavigationStack {
            TimelineHomeView(apiClient: client, cacheClientID: key, selectedTimeline: $selected,
                isActive: !covered, bottomContentInset: 80, homeViewModel: model)
                .overlay(alignment: .bottom) {
                    HStack {
                        Button("+20") { insert(20) }.accessibilityIdentifier("timeline.fixture.insert")
                        Button("覆盖") { covered.toggle() }.accessibilityIdentifier("timeline.fixture.cover")
                        Text("\(model.statuses.count)/\(model.newPostCount)")
                            .accessibilityIdentifier("timeline.fixture.count")
                            .accessibilityValue(model.lastLatestCheckAt.map { String($0.timeIntervalSince1970) } ?? "no-refresh")
                    }
                    .buttonStyle(.bordered)
                    .padding(8)
                    .background(.regularMaterial)
                }
        }
        .environment(\.appRouter, router)
        .environmentObject(appState)
        .moroTheme(MoroTheme(colorScheme: colorScheme))
    }

    private func insert(_ count: Int) {
        for _ in 0..<count {
            model.receiveLiveStatus(ThreadReadingFixtures.status("\(nextID)", own: false,
                content: "<p>Timeline fixture \(nextID)</p><p>New post body available immediately.</p>"))
            nextID += 1
        }
    }
}

final class TimelineLiveFixtureProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static func makeClient() -> MastodonClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://timeline-live-fixture.invalid")!,
            session: URLSession(configuration: config),
            authInterceptor: AuthInterceptor(tokenProvider: TimelineLiveFixtureToken()))
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isInitial = request.url!.path.contains("timelines") && query.isEmpty == false
                && !query.contains { $0.name == "max_id" || $0.name == "since_id" }
            let posts: [Status] = isInitial ? (41...100).reversed().map { id in
                ThreadReadingFixtures.status("\(id)", own: false, content:
                    "<p>Timeline fixture \(id)</p>" + String(repeating: "<p>这是用于验证阅读位置的长正文。自动插入后，这一段应该保持在原来的位置。</p>", count: id % 3 + 1))
            } : []
            let data = (try? encoder.encode(posts)) ?? Data("[]".utf8)
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
private final class TimelineLiveFixtureToken: AuthTokenProvider { var authToken: String? { "timeline-fixture" } }
#endif
