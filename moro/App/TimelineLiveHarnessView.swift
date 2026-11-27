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
        TimelineScrollBridge.probeEnabled = true
        let client = TimelineLiveFixtureProtocol.makeClient(testsGaps: testsGaps)
        self.testsGaps = testsGaps
        self.key = key
        self.client = client
        _model = StateObject(wrappedValue: TimelineViewModel(apiClient: client,
            accountCache: AccountCache(), feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(), cacheClientID: key, defersLivePresentation: true,
            markerSyncEnabled: { testsGaps }, restoresReadingPositionOverride: true))
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
                            Button("同步") {
                                TimelineLiveFixtureProtocol.latestInsertedID = 120
                                TimelineLiveFixtureProtocol.remoteMarkerID = "110"
                                TimelineLiveFixtureProtocol.nextHeadRefreshIDs = [120, 119]
                                Task { _ = await model.syncRemoteMarkerOnResume(allowAdvance: true) }
                            }
                            .accessibilityIdentifier("timeline.fixture.remoteSync")
                        } else {
                            Button("+20") {
                                TimelineScrollBridge.resetCommitProbe()
                                insert(20)
                            }.accessibilityIdentifier("timeline.fixture.insert")
                            // Largest reading-position displacement ever shown on screen
                            // during the last insertion (0 = no visible jump).
                            SwiftUI.TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                                Text("jump:\(Int(TimelineScrollBridge.maxCommittedAnchorDisplacement.rounded()))")
                                    .font(.caption2)
                                    .accessibilityIdentifier("timeline.fixture.jump")
                            }
                            Button("观察") { TimelineScrollBridge.beginWatch() }
                                .accessibilityIdentifier("timeline.fixture.watch")
                            SwiftUI.TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                                Text("watch:\(Int(TimelineScrollBridge.maxWatchedDeviation.rounded()))")
                                    .font(.caption2)
                                    .accessibilityIdentifier("timeline.fixture.watchResult")
                                    .accessibilityValue("frames:\(TimelineScrollBridge.watchedFrames)")
                            }
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
        TimelineLiveFixtureProtocol.latestInsertedID = max(TimelineLiveFixtureProtocol.latestInsertedID, latest)
        let ids = hasGap ? [latest] : [latest, latest - 1]
        model.receiveDetectedPage(TimelinePage(statuses: ids.map { TimelineLiveFixtureProtocol.post($0) }),
            sinceID: model.detectionBaselineID)
        nextID = latest + 1
    }
}

final class TimelineLiveFixtureProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var failNextGapRequest = false
    @MainActor static var latestInsertedID = 100
    @MainActor static var remoteMarkerID: String?
    @MainActor static var nextHeadRefreshIDs: [Int]?
    @MainActor static var hasServedInitialPage = false

    @MainActor static func makeClient(testsGaps: Bool = false) -> MastodonClient {
        latestInsertedID = 100
        remoteMarkerID = nil
        nextHeadRefreshIDs = nil
        hasServedInitialPage = false
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
            let path = request.url!.path
            if path == "/api/v1/markers" {
                let marker = Marker(
                    home: Self.remoteMarkerID.map {
                        MarkerContent(lastReadId: $0, updatedAt: Date(), version: 1)
                    },
                    notifications: nil
                )
                let data = (try? encoder.encode(marker)) ?? Data("{}".utf8)
                self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
                return
            }
            if path.hasPrefix("/api/v1/statuses/"),
                let idValue = Int(String(path.dropFirst("/api/v1/statuses/".count)))
            {
                let data = (try? encoder.encode(Self.post(idValue))) ?? Data("{}".utf8)
                self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
                return
            }

            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isInitial = path.contains("timelines") && query.isEmpty == false
                && !query.contains { $0.name == "max_id" || $0.name == "since_id" || $0.name == "min_id" }
            let isHeadRefresh = path.contains("timelines")
                && !query.contains { $0.name == "max_id" || $0.name == "min_id" }
            let posts: [Status]
            if isHeadRefresh, let headRefreshIDs = Self.nextHeadRefreshIDs {
                Self.nextHeadRefreshIDs = nil
                posts = headRefreshIDs.map(Self.post)
            } else if isInitial, !Self.hasServedInitialPage,
                ProcessInfo.processInfo.arguments.contains("UITEST_POST_EMOJI")
            {
                Self.hasServedInitialPage = true
                posts = [PostEmojiPlaybackFixture.post]
            } else if isInitial, !Self.hasServedInitialPage {
                Self.hasServedInitialPage = true
                posts = (41...100).reversed().map(Self.post)
            } else if request.value(forHTTPHeaderField: "X-Moro-Fixture-Gaps") == "1",
                let minLower = query.first(where: { $0.name == "min_id" })?.value.flatMap(Int.init)
            {
                if Self.failNextGapRequest {
                    Self.failNextGapRequest = false
                    self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                    return
                }
                let upper = min(minLower + 2, Self.latestInsertedID)
                posts = minLower < Self.latestInsertedID ? ((minLower + 1)...upper).reversed().map(Self.post) : []
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
