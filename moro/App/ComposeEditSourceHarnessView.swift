#if DEBUG
import SwiftUI

/// Exercises the production editor with an isolated transport and no signed-in account.
struct ComposeEditSourceHarnessView: View {
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let client: MastodonClient
    private let status: Status

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EditSourceFixtureProtocol.self]
        client = MastodonClient(
            baseURL: URL(string: "https://edit-source-fixture.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: EditSourceFixtureTokenProvider())
        )
        let account = Account(
            id: "fixture-author", username: "moro", acct: "moro", displayName: "Moro",
            note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
            followersCount: 0, followingCount: 0, statusesCount: 1
        )
        status = Status(
            id: "fixture-edit", content: "<p>原文 https://example.com/a/very…</p>",
            createdAt: Date(), account: account, mediaAttachments: [],
            favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
            bookmarked: false, favourited: false, reblogged: false
        )
    }

    var body: some View {
        ComposeView(context: .edit(status: status), apiClient: client)
            .environmentObject(appState)
            .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
    }
}

private final class EditSourceFixtureTokenProvider: AuthTokenProvider {
    var authToken: String? { "fixture-token" }
}

private final class EditSourceFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var sourceRequests = 0
    private var responseTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isSource = request.httpMethod == "GET" && request.url?.path.hasSuffix("/source") == true
        let attempt = Self.lock.withLock {
            if isSource { Self.sourceRequests += 1 }
            return Self.sourceRequests
        }
        responseTask = Task {
            do {
                // Leave enough time for UI tests to observe the initial disabled editor.
                if isSource && attempt == 1 { try await Task.sleep(for: .seconds(6)) }
                try Task.checkCancellation()
                let statusCode = isSource ? (attempt == 1 ? 503 : 200) : 404
                let object: [String: String] = isSource && attempt > 1
                    ? ["id": "fixture-edit", "text": "原文：https://example.com/a/very/long/path?first=1&second=2\n@alice@remote.example 我用 #Swift 写了一个 App。😀", "spoiler_text": ""]
                    : ["error": "Fixture response"]
                let data = try JSONSerialization.data(withJSONObject: object)
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: statusCode, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
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
