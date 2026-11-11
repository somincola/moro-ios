import AVFoundation
import Foundation
import Testing
@testable import moro

@MainActor
struct ComposeVideoTests {
    @Test func mediaTransfersHaveALongerBudgetWithoutSlowingOrdinaryAPIRequests() {
        #expect(MastodonClient.defaultSession.configuration.timeoutIntervalForResource == 40)
        #expect(MastodonClient.defaultMediaUploadSession.configuration.timeoutIntervalForResource == 600)
        #expect(MastodonClient.defaultMediaUploadSession.configuration.timeoutIntervalForRequest == 120)
    }

    @Test func videoReservationsRejectMixedSelectionsAndReleaseTheirSlotWhenRemoved() throws {
        let model = ComposeViewModel(context: .newPost, apiClient: MockMastodonAPI())
        model.isPublishing = true
        #expect(model.reserveMediaImports(types: ["video"]).isEmpty)
        model.isPublishing = false
        #expect(model.reserveMediaImports(types: ["image", "video"]).isEmpty)
        #expect(model.reserveMediaImports(types: ["video", "video"]).isEmpty)
        #expect(model.mediaAttachments.isEmpty)
        let id = try #require(model.reserveMediaImports(types: ["video"]).first)
        #expect(model.hasVideoAttachment && !model.canAddMedia)
        #expect(model.reservePhotoImports(count: 1).isEmpty)
        #expect(model.removeMedia(id: id))
        #expect(model.canAddMedia && model.remainingMediaAttachmentSlots == 4)
        #expect(model.reservePhotoImports(count: 1).count == 1)
        #expect(model.reserveMediaImports(types: ["video"]).isEmpty)
    }

    @Test func preparedVideoCannotBypassTheRuleAfterAnImageArrives() async throws {
        let model = ComposeViewModel(context: .newPost, apiClient: MockMastodonAPI())
        #expect(model.reservePhotoImports(count: 1).count == 1)
        let outcome = await model.importPreparedMedia(.init(
            uploadData: Data([1]), uploadMimeType: "video/mp4", mediaType: "video", previewImage: nil))
        #expect(outcome == .failed(.videoMustBeAlone))
        #expect(model.mediaAttachments.map(\.type) == ["image"])
    }

    @Test func restoredMixedMediaCannotBePublished() async throws {
        let model = ComposeViewModel(context: .newPost, apiClient: MockMastodonAPI())
        model.mediaAttachments = ["image", "video"].map {
            MediaAttachment(id: $0, url: URL(string: "https://video.invalid/\($0)")!,
                previewURL: nil, type: $0, description: nil, focus: nil, uploadState: .uploaded)
        }
        #expect(model.publishBlocker == .videoMustBeAlone)
        do {
            _ = try await model.publish()
            Issue.record("An invalid restored draft must not reach the server")
        } catch ComposeError.videoMustBeAlone {}
    }

    @Test func instanceVideoSizeLimitIsDecodedAndApplied() async throws {
        let configuration = try JSONDecoder().decode(InstanceConfiguration.self,
            from: Data(#"{"media_attachments":{"video_size_limit":1234567}}"#.utf8))
        let api = MockMastodonAPI()
        api.fetchInstanceV2Handler = {
            .init(domain: "video.invalid", title: "Video", description: nil, thumbnail: nil, contact: nil,
                registrations: nil, rules: nil, languages: nil, configuration: configuration)
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api)
        await model.loadInstanceLimits()
        #expect(model.videoSizeLimit == 1_234_567)
        #expect(ComposeMediaSelectionPolicy.videoSizeLimit(reportedByInstance: 0)
            == ComposeMediaSelectionPolicy.defaultVideoSizeLimit)
    }

    @Test func pickerOwnsItsVideoUntilImportCompletesAndBuildsAThumbnail() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("video-source-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        try await TimelineMediaFixture.makeVideo(at: source)
        let original = try Data(contentsOf: source)
        let video = try ComposePickedVideo(copying: source)
        defer { video.removeTemporaryFile() }
        try FileManager.default.removeItem(at: source)
        let prepared = try await ComposeMediaProcessor.shared.prepareVideoFile(
            at: video.url, mimeType: video.mimeType, sizeLimit: 1_000_000)
        #expect(prepared.uploadData == original)
        #expect(prepared.uploadMimeType == "video/mp4" && prepared.mediaType == "video")
        #expect(prepared.previewImage != nil)
        video.removeTemporaryFile()
        #expect(!FileManager.default.fileExists(atPath: video.url.path))
    }

    @Test func oversizedVideoIsReencodedWithoutChangingTheSource() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("video-large-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        try await TimelineMediaFixture.makeVideo(at: source)
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0, count: 1_000_000))
        try handle.close()
        let size = try #require(source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let prepared = try await ComposeMediaProcessor.shared.prepareVideoFile(
            at: source, mimeType: "video/mp4", sizeLimit: 500_000)
        #expect(prepared.uploadData.count < 500_000 && !prepared.uploadData.isEmpty)
        #expect(prepared.uploadMimeType == "video/mp4")
        #expect(prepared.previewImage != nil)
        #expect(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize == size)
    }

    @Test func aVideoStillTooLargeAfterCompressionIsRejected() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("video-limit-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        try await TimelineMediaFixture.makeVideo(at: source)
        do {
            _ = try await ComposeMediaProcessor.shared.prepareVideoFile(at: source, mimeType: "video/mp4", sizeLimit: 1)
            Issue.record("A video above the server limit must not be uploaded")
        } catch ComposeMediaProcessor.ProcessingError.videoTooLarge {}
    }

    @Test func uploadProcessingBlocksPublishingUntilTheReadyResponse() async throws {
        let (client, host) = makeClient("async")
        let model = ComposeViewModel(context: .newPost, apiClient: client)
        let task = Task { await model.importPreparedMedia(.init(
            uploadData: Data([1]), uploadMimeType: "video/mp4", mediaType: "video", previewImage: nil)) }
        defer { task.cancel() }
        try await wait { !VideoUploadProtocol.paths(for: host).isEmpty }
        #expect(model.hasUploadingMedia && !model.canPublish)
        do {
            _ = try await model.publish()
            Issue.record("Publishing must wait for the server to finish processing")
        } catch ComposeError.mediaUploading {}
        #expect(await task.value == .uploaded)
        #expect(model.canPublish && model.mediaAttachments.first?.type == "video")
        #expect(model.mediaAttachments.first?.url.absoluteString == "https://video.invalid/ready.mp4")
        #expect(VideoUploadProtocol.paths(for: host) == ["POST /api/v2/media", "GET /api/v1/media/video", "GET /api/v1/media/video"])
    }

    @Test func synchronousUploadDoesNotPoll() async throws {
        let (client, host) = makeClient("sync")
        let attachment = try await client.uploadMedia(data: Data([1]), mimeType: "image/jpeg", description: nil)
        #expect(attachment.type == "image")
        #expect(VideoUploadProtocol.paths(for: host) == ["POST /api/v2/media"])
    }

    @Test func serverProcessingFailureEndsTheUpload() async throws {
        let (client, host) = makeClient("failure")
        await #expect(throws: APIError.self) {
            try await client.uploadMedia(data: Data([1]), mimeType: "video/mp4", description: nil)
        }
        #expect(VideoUploadProtocol.paths(for: host) == ["POST /api/v2/media", "GET /api/v1/media/video"])
    }

    @Test func cancellingAnUploadStopsProcessingPolls() async throws {
        let (client, host) = makeClient("cancel")
        let task = Task { try await client.uploadMedia(data: Data([1]), mimeType: "video/mp4", description: nil) }
        defer { task.cancel() }
        try await wait { VideoUploadProtocol.paths(for: host).count >= 2 }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(VideoUploadProtocol.paths(for: host).count == 2)
    }

    private func makeClient(_ scenario: String) -> (MastodonClient, String) {
        let host = "\(scenario)-\(UUID().uuidString).video-upload.invalid"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoUploadProtocol.self]
        return (MastodonClient(baseURL: URL(string: "https://\(host)")!, session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: VideoUploadToken())), host)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(condition())
    }
}

private final class VideoUploadToken: AuthTokenProvider {
    var authToken: String? { "video-fixture" }
}

nonisolated private final class VideoUploadProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests: [String: [String]] = [:]

    static func paths(for host: String) -> [String] { lock.withLock { requests[host] ?? [] } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".video-upload.invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let host = url.host!
        let count = Self.lock.withLock {
            Self.requests[host, default: []].append("\(request.httpMethod ?? "GET") \(url.path)")
            return Self.requests[host]!.count
        }
        var status = 200
        var payload: [String: Any] = ["id": "video", "type": "video",
            "url": "https://video.invalid/ready.mp4", "preview_url": "https://video.invalid/preview.jpg"]
        if url.path == "/api/v2/media", !host.hasPrefix("sync-") {
            status = 202
            payload["url"] = NSNull()
        } else if host.hasPrefix("sync-") {
            payload["type"] = "image"
        } else if host.hasPrefix("failure-") {
            status = 422
            payload = ["error": "Video processing failed"]
        } else if host.hasPrefix("cancel-") || count == 2 {
            status = 206
            payload["url"] = NSNull()
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
