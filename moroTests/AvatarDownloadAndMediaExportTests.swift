import AVFoundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import moro

@MainActor @Suite(.serialized)
struct AvatarDownloadAndMediaExportTests {
    @Test func avatarDownloadRejectsDeclaredAndStreamedOversizeBodies() async {
        for path in ["declared-oversize", "streamed-oversize", "http-error"] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AvatarDownloadProtocol.self]
            await #expect(throws: URLError.self) {
                try await BoundedAvatarDownload.load(URL(string: "https://avatar-download.invalid/\(path)")!,
                    configuration: configuration)
            }
        }
    }

    @Test func avatarDownloadHonorsNoStoreAndSupportsCancellationBeforeStart() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarDownloadProtocol.self]
        let result = try await BoundedAvatarDownload.load(URL(string: "https://avatar-download.invalid/no-store")!,
            configuration: configuration)
        #expect(result.data == Data("GIF89a".utf8))
        #expect(!result.cacheable)
        let task = Task {
            try await BoundedAvatarDownload.load(URL(string: "https://avatar-download.invalid/cancel")!,
                configuration: configuration)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func GIFVExportKeepsThePlayableOriginalAndGIFExportKeepsAnimationBytes() async throws {
        try await TimelineMediaFixture.prepare()
        let video = try await MediaExportService.loadVideo(from: TimelineMediaFixture.videoURL)
        defer { try? FileManager.default.removeItem(at: video.url.deletingLastPathComponent()) }
        #expect(video.url.pathExtension == "mp4")
        #expect(try Data(contentsOf: video.url) == Data(contentsOf: TimelineMediaFixture.videoURL))
        #expect(try await AVURLAsset(url: video.url).loadTracks(withMediaType: .video).count == 1)
        let image = try await MediaExportService.loadImage(from: TimelineMediaFixture.avatarURL)
        #expect(image.type.conforms(to: .gif))
        #expect(image.data == (try Data(contentsOf: TimelineMediaFixture.avatarURL)))
    }

    @Test func videoMenusOnlyOfferFileActionsAndInvalidMediaIsRejected() async throws {
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID()).mp4")
        try Data("not a movie".utf8).write(to: invalid)
        defer { try? FileManager.default.removeItem(at: invalid) }
        let gifv = Status.Attachment(id: "gifv", type: "gifv", url: invalid)
        #expect(MediaExportAction.available(for: gifv) == [.save, .share])
        #expect(MediaExportAction.available(for: .init(id: "gif", type: "image", url: invalid)) == [.save, .share, .copy])
        await #expect(throws: MediaExportService.ExportError.self) {
            try await MediaExportService.loadVideo(from: invalid)
        }
    }

    @Test func aParkedVideoExpiresButAnActiveVideoOutlivesTheOldTimer() async throws {
        let pool = TimelineVideoPlayerPool(warmLifetime: 0.08)
        let url = URL(string: "https://10.255.255.1/expiry-\(UUID()).mp4")!
        let entry = pool.acquire(url: url, isGIF: false, loops: false)
        pool.release(entry)
        #expect(pool.parkedCount == 1)
        #expect(pool.acquire(url: url, isGIF: false, loops: false) === entry)
        try await Task.sleep(for: .milliseconds(150))
        #expect(entry.player.currentItem != nil)
        pool.release(entry)
        let deadline = ContinuousClock.now + .seconds(15)
        while pool.parkedCount > 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(pool.parkedCount == 0)
        #expect(entry.player.currentItem == nil)
    }
}

nonisolated private final class AvatarDownloadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "avatar-download.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        var headers = ["Cache-Control": "no-store"]
        if path == "declared-oversize" { headers["Content-Length"] = "\(AvatarAnimationLimits.maximumFileBytes + 1)" }
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "http-error" ? 500 : 200,
                                      httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "streamed-oversize" {
            client?.urlProtocol(self, didLoad: Data(repeating: 1, count: AvatarAnimationLimits.maximumFileBytes))
            client?.urlProtocol(self, didLoad: Data([1]))
        } else { client?.urlProtocol(self, didLoad: Data("GIF89a".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
