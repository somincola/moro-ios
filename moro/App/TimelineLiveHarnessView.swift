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
    private let testsGaps: Bool

    init() {
        let key = "timeline-live-ui-\(UUID().uuidString)"
        let testsGaps = ProcessInfo.processInfo.arguments.contains("UITEST_TIMELINE_GAPS")
        let client = TimelineLiveFixtureProtocol.makeClient(testsGaps: testsGaps)
        self.testsGaps = testsGaps
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
                        if testsGaps {
                            Button("完整更新") { insertHead(hasGap: false) }
                                .accessibilityIdentifier("timeline.fixture.complete")
                            Button("缺口") { insertHead(hasGap: true) }
                                .accessibilityIdentifier("timeline.fixture.gap")
                            Button("失败") {
                                TimelineLiveFixtureProtocol.failNextGapRequest = true
                                insertHead(hasGap: true)
                            }
                            .accessibilityIdentifier("timeline.fixture.gapFailure")
                        } else {
                            Button("+20") { insert(20) }.accessibilityIdentifier("timeline.fixture.insert")
                            Button("覆盖") { covered.toggle() }.accessibilityIdentifier("timeline.fixture.cover")
                        }
                        Text("\(model.statuses.count)/\(model.newPostCount)")
                            .accessibilityIdentifier("timeline.fixture.count")
                            .accessibilityValue(testsGaps
                                ? "gaps:\(model.gaps.count);failed:\(model.failedGapIDs.count)"
                                : model.lastLatestCheckAt.map { String($0.timeIntervalSince1970) } ?? "no-refresh")
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

    private func insertHead(hasGap: Bool) {
        let latest = nextID + (hasGap ? 7 : 1)
        let ids = hasGap ? [latest] : [latest, latest - 1]
        model.receiveDetectedPage(TimelinePage(statuses: ids.map { TimelineLiveFixtureProtocol.post($0) }),
            sinceID: model.detectionBaselineID)
        nextID = latest + 1
    }
}

final class TimelineLiveFixtureProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var failNextGapRequest = false

    @MainActor static func makeClient(testsGaps: Bool = false) -> MastodonClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Self.self]
        if testsGaps { config.httpAdditionalHeaders = ["X-Moro-Fixture-Gaps": "1"] }
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
            let posts: [Status]
            if isInitial {
                posts = (41...100).reversed().map(Self.post)
            } else if request.value(forHTTPHeaderField: "X-Moro-Fixture-Gaps") == "1",
                let upper = query.first(where: { $0.name == "max_id" })?.value.flatMap(Int.init),
                let lower = query.first(where: { $0.name == "since_id" })?.value.flatMap(Int.init)
            {
                if Self.failNextGapRequest {
                    Self.failNextGapRequest = false
                    self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                    return
                }
                posts = upper > lower + 1 ? ((lower + 1)..<upper).reversed().prefix(2).map(Self.post) : []
            } else {
                posts = []
            }
            let data = (try? encoder.encode(posts)) ?? Data("[]".utf8)
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}

    @MainActor static func post(_ id: Int) -> Status {
        ThreadReadingFixtures.status("\(id)", own: false, content:
            "<p>Timeline fixture \(id)</p>" + String(repeating: "<p>这是用于验证阅读位置的长正文。自动插入后，这一段应该保持在原来的位置。</p>", count: id % 3 + 1))
    }
}
private final class TimelineLiveFixtureToken: AuthTokenProvider { var authToken: String? { "timeline-fixture" } }
#endif
