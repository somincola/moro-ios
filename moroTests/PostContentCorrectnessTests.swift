import Foundation
import Testing
@testable import moro

@Suite(.serialized)
@MainActor
struct PostContentCorrectnessTests {
    private let sourceText = "原文： https://example.com/a/very/long/path?first=1&second=2\n@alice@example.social #Swift :wave:"

    @Test func editingUsesAuthenticatedSourceAndPreservesTheEntirePost() async throws {
        let original = try makeStatus(sensitive: true, withMedia: true)
        let response = try encoded(original)
        let source = try sourceData()
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            await recorder.record(request)
            return (200, request.url!.path.hasSuffix("/source") ? source : response)
        }
        let model = ComposeViewModel(context: .edit(status: original), apiClient: client, feedCoordinator: FeedCoordinator())

        #expect(model.content.isEmpty)
        #expect(!model.canPublish)
        #expect(!model.hasDraftableContent)
        await model.loadEditingSourceIfNeeded()
        #expect(model.content == sourceText)
        #expect(model.contentWarning == "")
        #expect(model.isEditingSourceReady)
        _ = try await model.publish()

        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.path == "/api/v1/statuses/edit-1/source")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        #expect(requests[1].httpMethod == "PUT")
        let body = try requestBody(requests[1])
        #expect(body["status"] as? String == sourceText)
        #expect(body["media_ids"] as? [String] == ["media-1"])
        #expect(body["sensitive"] as? Bool == true)
        #expect(body["language"] as? String == "fr")
        #expect(body["spoiler_text"] as? String == "")
        for key in ["visibility", "in_reply_to_id", "quoted_status_id", "quote_id", "quote_approval_policy", "scheduled_at", "poll"] {
            #expect(body[key] == nil, "Editing unexpectedly sent \(key)")
        }
    }

    @Test func editingExplicitlyClearsWarningAndRemovedAttachments() async throws {
        let original = try makeStatus(spoilerText: "旧警告", sensitive: true, withMedia: true)
        let source = try sourceData(spoilerText: "旧警告")
        let response = try encoded(original)
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            await recorder.record(request)
            return (200, request.url!.path.hasSuffix("/source") ? source : response)
        }
        let model = ComposeViewModel(context: .edit(status: original), apiClient: client, feedCoordinator: FeedCoordinator())
        await model.loadEditingSourceIfNeeded()
        #expect(model.contentWarning == "旧警告")
        #expect(model.isContentWarningActive)
        model.isContentWarningActive = false
        model.removeMedia(id: "media-1")
        model.content += "\n只增加这一句。"
        _ = try await model.publish()

        let request = try #require(await recorder.requests.last)
        let body = try requestBody(request)
        #expect(body["status"] as? String == sourceText + "\n只增加这一句。")
        #expect(body["spoiler_text"] as? String == "")
        #expect(body["media_ids"] as? [String] == [])
        #expect(body["sensitive"] as? Bool == false)
    }

    @Test func failedSourceLoadCannotPublishAndCanRetry() async throws {
        let original = try makeStatus(withMedia: true)
        let source = try sourceData()
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            let count = await recorder.record(request)
            return count == 1 ? (503, Data(#"{"error":"temporary failure"}"#.utf8)) : (200, source)
        }
        let model = ComposeViewModel(context: .edit(status: original), apiClient: client)
        await model.loadEditingSourceIfNeeded()
        #expect(model.editSourceState == .failed)
        #expect(model.publishBlocker == .editSourceUnavailable)
        do {
            _ = try await model.publish()
            Issue.record("An edit without its original source must not be submitted")
        } catch ComposeError.editSourceUnavailable { }
        #expect(await recorder.requests.count == 1)

        await model.loadEditingSourceIfNeeded()
        #expect(model.content == sourceText)
        #expect(model.canPublish)
        model.content += " changed"
        await model.loadEditingSourceIfNeeded()
        #expect(await recorder.requests.count == 2)
        #expect(model.content == sourceText + " changed")
    }

    @Test func lateSourceResponseDoesNotReplaceUserChanges() async throws {
        let original = try makeStatus()
        let source = try sourceData(spoilerText: "原警告")
        let gate = PostResponseGate()
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            await recorder.record(request)
            await gate.wait()
            return (200, source)
        }
        let model = ComposeViewModel(context: .edit(status: original), apiClient: client)
        let loading = Task { await model.loadEditingSourceIfNeeded() }
        await recorder.waitForFirstRequest()
        #expect(model.editSourceState == .loading)
        model.content = "用户已经恢复的草稿 https://example.com/full-link"
        model.contentWarning = "用户警告"
        model.isContentWarningActive = true
        await gate.open()
        await loading.value
        #expect(model.content == "用户已经恢复的草稿 https://example.com/full-link")
        #expect(model.contentWarning == "用户警告")
        #expect(model.isContentWarningActive)
        #expect(model.isEditingSourceReady)
    }

    @Test func cancelledSourceLoadCanRestart() async throws {
        let original = try makeStatus()
        let source = try sourceData()
        let gate = PostResponseGate()
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            let count = await recorder.record(request)
            if count == 1 { await gate.wait() }
            return (200, source)
        }
        let model = ComposeViewModel(context: .edit(status: original), apiClient: client)
        let loading = Task { await model.loadEditingSourceIfNeeded() }
        await recorder.waitForFirstRequest()
        loading.cancel()
        await gate.open()
        await loading.value
        #expect(model.editSourceState == .pending)
        #expect(model.content.isEmpty)
        await model.loadEditingSourceIfNeeded()
        #expect(model.content == sourceText)
    }

    @Test(arguments: [false, true])
    func restoredDraftKeepsIntentionallyEmptyTextAndWarning(restoreWhileLoading: Bool) async throws {
        let original = try makeStatus(withMedia: true)
        let source = try sourceData(spoilerText: "服务器警告")
        let gate = PostResponseGate()
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            await recorder.record(request)
            await gate.wait()
            return (200, source)
        }
        let draftModel = ComposeViewModel(context: .newPost, apiClient: client)
        draftModel.addMedia(try #require(original.mediaAttachments.first))
        let draft = draftModel.makeDraft(category: .manual)
        let model = ComposeViewModel(
            context: .edit(status: original), apiClient: client,
            initialDraft: restoreWhileLoading ? nil : draft
        )
        let loading = Task { await model.loadEditingSourceIfNeeded() }
        await recorder.waitForFirstRequest()
        if restoreWhileLoading { model.applyRestoredDraft(draft) }
        await gate.open()
        await loading.value

        #expect(model.content.isEmpty)
        #expect(model.contentWarning.isEmpty)
        #expect(!model.isContentWarningActive)
        #expect(model.mediaAttachments.map(\.id) == ["media-1"])
        #expect(model.canPublish)
    }

    @Test(arguments: [ComposeViewModel.QuotePolicy.anyone, .followers, .none])
    func quoteSelectionReachesTheActualRequest(policy: ComposeViewModel.QuotePolicy) async throws {
        let original = try makeStatus()
        let response = try encoded(original)
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            await recorder.record(request)
            return (200, response)
        }
        for context: ComposeViewModel.ComposeContext in [.newPost, .reply(to: original), .quote(original: original)] {
            let model = ComposeViewModel(context: context, apiClient: client, feedCoordinator: FeedCoordinator())
            model.content = "正文"
            model.visibility = .public
            model.quotePolicy = policy
            _ = try await model.publish()
            let request = try #require(await recorder.requests.last)
            let body = try requestBody(request)
            #expect(request.httpMethod == "POST")
            #expect(body["quote_approval_policy"] as? String == policy.apiValue.rawValue)
            #expect(body["quote_id"] == nil)
            if case .quote = context {
                #expect(body["quoted_status_id"] as? String == original.id)
            } else {
                #expect(body["quoted_status_id"] == nil)
            }
            if case .reply = context {
                #expect(body["in_reply_to_id"] as? String == original.id)
            }
        }
        #expect(ComposeViewModel.QuotePolicy(rawValue: "none")?.apiValue == .nobody)
    }

    @Test(arguments: [MastodonVisibility.followers, .direct, ._other("circle")])
    func restrictedVisibilityUsesSelfOnlyQuotePolicy(visibility: MastodonVisibility) async throws {
        let response = try encoded(makeStatus())
        let recorder = PostRequestRecorder()
        let client = makeClient { request in
            await recorder.record(request)
            return (200, response)
        }
        let model = ComposeViewModel(context: .newPost, apiClient: client, feedCoordinator: FeedCoordinator())
        model.content = "正文"
        model.visibility = visibility
        model.quotePolicy = .anyone
        _ = try await model.publish()
        let request = try #require(await recorder.requests.last)
        #expect(try requestBody(request)["quote_approval_policy"] as? String == "nobody")
    }

    private func makeClient(handler: @escaping PostContentURLProtocol.Handler) -> MastodonClient {
        PostContentURLProtocol.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PostContentURLProtocol.self]
        return MastodonClient(
            baseURL: URL(string: "https://moro-content-tests.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: PostFixtureTokenProvider())
        )
    }

    private func sourceData(spoilerText: String = "") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": "edit-1", "text": sourceText, "spoiler_text": spoilerText])
    }

    private func makeStatus(spoilerText: String = "", sensitive: Bool = false, withMedia: Bool = false) throws -> Status {
        let attachments = withMedia ? [Status.Attachment(
            id: "media-1", type: "image", url: URL(string: "https://example.com/image.png")!, description: "保留 ALT"
        )] : []
        let account = Account(
            id: "author-1", username: "author", acct: "author", displayName: "Author",
            note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
            followersCount: 0, followingCount: 0, statusesCount: 1
        )
        let status = Status(
            id: "edit-1",
            content: #"<p>原文：<a href="https://example.com/a/very/long/path?first=1&amp;second=2"><span class="invisible">https://</span><span class="ellipsis">example.com/a/very</span><span class="invisible">/long/path?first=1&amp;second=2</span></a></p>"#,
            createdAt: Date(),
            account: account,
            mediaAttachments: attachments,
            favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
            bookmarked: false, favourited: false, reblogged: false,
            inReplyToID: "parent-1",
            spoilerText: spoilerText,
            visibility: "unlisted",
            language: "fr"
        )
        var object = try #require(JSONSerialization.jsonObject(with: encoded(status)) as? [String: Any])
        object["sensitive"] = sensitive
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Status.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func encoded(_ status: Status) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(status)
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try #require(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var body = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            data = body
        }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class PostFixtureTokenProvider: AuthTokenProvider {
    var authToken: String? { "fixture-token" }
}

private actor PostRequestRecorder {
    private(set) var requests: [URLRequest] = []
    private var firstRequestWaiter: CheckedContinuation<Void, Never>?

    @discardableResult
    func record(_ request: URLRequest) -> Int {
        // URLSession can present the body as a stream. Capture it before it is consumed.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            stream.close()
            captured.httpBody = data
        }
        requests.append(captured)
        firstRequestWaiter?.resume()
        firstRequestWaiter = nil
        return requests.count
    }

    func waitForFirstRequest() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { firstRequestWaiter = $0 }
    }
}

private actor PostResponseGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

private final class PostContentURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, Data)
    private static let lock = NSLock()
    private static var handler: Handler?
    private var responseTask: Task<Void, Never>?

    static func setHandler(_ handler: @escaping Handler) {
        lock.withLock { Self.handler = handler }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.lock.withLock({ Self.handler }) else { return }
        responseTask = Task {
            do {
                let (code, data) = try await handler(request)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}
