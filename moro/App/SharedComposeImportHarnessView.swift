#if DEBUG
import Combine
import SwiftUI

/// Exercises the production editor, receiver and App Group with a transport that
/// never sends user content to a server. The system scenario is launched from Photos.
struct SharedComposeImportHarnessView: View {
    @StateObject private var fixture = SharedComposeFixture()
    @StateObject private var root = RootTabCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 20) {
            Button("Share two images") { fixture.stage(count: 2); receive() }
                .accessibilityIdentifier("shareFixture.stage")
            Button("Existing editor") { root.openCompose(draft: fixture.existingDraft) }
                .accessibilityIdentifier("shareFixture.existing")
            Text(fixture.summary).accessibilityIdentifier("shareFixture.summary")
        }
        .fullScreenCover(item: $root.composeContext, onDismiss: { fixture.refresh(); receive() }) { wrapper in
            ComposeView(context: wrapper.context, apiClient: fixture.client, currentUserID: fixture.account.id,
                draftStore: fixture.store, initialDraft: wrapper.draft, sharedImport: wrapper.sharedImport,
                onDismiss: { root.composeContext = nil }) { _ in fixture.refresh() }
                .environmentObject(fixture.appState)
                .safeAreaInset(edge: .bottom) {
                    if fixture.scenario != "system" {
                        HStack {
                            Button("Incoming images") { fixture.stage(count: 2) }
                                .accessibilityIdentifier("shareFixture.incoming")
                            Text(fixture.summary).font(.caption)
                                .accessibilityIdentifier("shareFixture.editorSummary")
                        }
                        .padding(8).background(.thinMaterial)
                    }
                }
        }
        .onAppear { receive() }
        .onReceive(NotificationCenter.default.publisher(for: SharedComposeHandoff.received)) { _ in receive() }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in fixture.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { receive() } }
    }

    private func receive() {
        guard scenePhase == .active else { return }
        _ = root.presentPendingSharedImport(using: SharedComposeImportCoordinator(draftStore: fixture.store),
            accountID: fixture.account.id)
    }
}

@MainActor
private final class SharedComposeFixture: ObservableObject {
    let account = Account(id: "share-fixture", username: "tester", acct: "tester", displayName: "Tester",
        note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
        followersCount: 0, followingCount: 0, statusesCount: 0)
    let appState = AppState()
    let store: ComposeDraftStore
    let client: MastodonClient
    let scenario = ProcessInfo.processInfo.environment["UITEST_SHARE_SCENARIO"] ?? "normal"
    @Published private(set) var summary = ""
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("share-fixture-\(UUID())")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging: SharedComposeDraftStagingStore
        if scenario == "system" {
            staging = .shared
            // A previous interrupted UI run may have left fixture-only files behind.
            for item in staging.pendingItems() where item.accountID == "share-fixture" {
                staging.removeItem(id: item.id)
            }
        }
        else {
            staging = SharedComposeDraftStagingStore(userDefaults: UserDefaults(suiteName: "ui-share-staging-\(UUID())")!,
                baseDirectoryURL: directory.appendingPathComponent("staging"))
        }
        store = ComposeDraftStore(userDefaults: UserDefaults(suiteName: "ui-share-drafts-\(UUID())")!, stagingStore: staging)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SharedComposeFixtureProtocol.self]
        client = MastodonClient(baseURL: URL(string: "https://\(UUID().uuidString).share-fixture.invalid")!,
            session: URLSession(configuration: configuration), authInterceptor: AuthInterceptor(tokenProvider: SharedComposeFixtureToken()))
        appState.currentAccount = account
        if scenario == "system" {
            // No token, login or real account is written into the shared container.
            let snapshot = try? JSONSerialization.data(withJSONObject: ["account": ["id": account.id]])
            MoroSharedContainer.sharedUserDefaults().set(snapshot, forKey: "shared_active_account_session_snapshot_v1")
        }
        refresh()
    }

    var existingDraft: ComposeDraft {
        let model = ComposeViewModel(context: .newPost, apiClient: client, currentUserID: account.id)
        model.content = "Existing words"
        if scenario == "limit" {
            model.mediaAttachments = (0..<3).map { MediaAttachment(id: "existing-\($0)",
                url: imageURL("existing-\($0)"), previewURL: nil, type: "image", description: "Existing", focus: nil,
                uploadState: .uploaded) }
        }
        return model.makeDraft(category: .auto)
    }

    func stage(count: Int) {
        do {
            let source = directory.appendingPathComponent("image.png")
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
            let image = renderer.image { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            }
            try image.pngData()!.write(to: source)
            let model = ComposeViewModel(context: .newPost, apiClient: client, currentUserID: account.id)
            model.content = "Shared words"
            let item = try store.stageSharedDraft(accountID: account.id, target: .init(kind: .newPost),
                payload: model.makeDraft(category: .auto).payload,
                attachments: (0..<count).map { _ in .init(sourceURL: source, mimeType: "image/png", id: UUID().uuidString) })
            SharedComposeHandoff.shared.receive(URL(string: "moro://share/compose?item=\(item.id)")!)
            refresh()
        } catch { summary = "Fixture failed: \(error.localizedDescription)" }
    }

    func refresh() {
        let drafts = store.drafts(for: account.id)
        let requests = SharedComposeFixtureProtocol.counts
        let value = "Manual: \(drafts.filter { $0.category == .manual }.count); files: \(store.pendingSharedStagingItems().reduce(0) { $0 + $1.attachments.count }); uploads: \(requests.uploads); posts: \(requests.posts)"
        if summary != value { summary = value }
    }

    private func imageURL(_ id: String) -> URL {
        let url = directory.appendingPathComponent("\(id).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            }
            try? image.pngData()?.write(to: url)
        }
        return url
    }

    nonisolated deinit {}
}

private final class SharedComposeFixtureToken: AuthTokenProvider {
    var authToken: String? { "local-fixture" }
}

private final class SharedComposeFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var uploads = 0
    private static var posts = 0
    static var counts: (uploads: Int, posts: Int) { lock.withLock { (uploads, posts) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let url = request.url!
            let data: Data
            if url.path == "/api/v2/media" {
                let count = Self.lock.withLock { Self.uploads += 1; return Self.uploads }
                if ProcessInfo.processInfo.environment["UITEST_SHARE_SCENARIO"] == "retry", count == 2 {
                    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
                }
                let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                    UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
                }
                let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("share-upload-\(count).png")
                try image.pngData()!.write(to: imageURL)
                // The production grid reads this local URL through its regular image loader.
                data = try JSONSerialization.data(withJSONObject: ["id": "upload-\(count)", "type": "image",
                    "url": imageURL.absoluteString, "preview_url": imageURL.absoluteString, "description": "Shared image"])
            } else if url.path == "/api/v1/statuses", request.httpMethod == "POST" {
                Self.lock.withLock { Self.posts += 1 }
                data = try JSONSerialization.data(withJSONObject: DirectMessagesFixtureProtocol.status("shared-post", author: "tester", content: "<p>Shared post</p>"))
            } else if url.path.contains("/instance") {
                data = try JSONSerialization.data(withJSONObject: ["uri": url.host!, "title": "Share fixture", "version": "4.5.0"])
            } else { data = Data("[]".utf8) }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
#endif
