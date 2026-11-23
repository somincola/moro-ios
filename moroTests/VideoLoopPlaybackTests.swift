import AVFoundation
import Combine
import CoreVideo
import Foundation
import XCTest
@testable import moro

// These tests play real media. Run them in the XCTest phase, before the parallel
// Swift Testing suites that reconfigure the process-wide audio session.
@MainActor
final class VideoLoopPlaybackTests: XCTestCase {
    func testQueuedEndCallbackCannotStopANewLeaseOfTheSamePlayer() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-generation-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeShortVideo(at: url)
        let pool = TimelineVideoPlayerPool()
        let observer = VideoPlayerObserver(pool: pool)
        defer {
            observer.tearDown()
            pool.removeAll()
        }
        observer.setPlayer(url: url, isGIF: true, shouldLoop: false)
        let player = try XCTUnwrap(observer.getPlayer())
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
        observer.tearDown()
        observer.setPlayer(url: url, isGIF: true, shouldLoop: false)
        XCTAssertTrue(observer.getPlayer() === player)
        // Let the queued callback run before anything plays: the clip is half a second long,
        // so once it plays a slow runner can genuinely reach its end before the check.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(observer.didReachEnd)
        observer.play()
        XCTAssertTrue(observer.isPlaybackRequested)
    }

    func testManuallyStartedGIFVideoPlaysOnceAndCanBeReplayed() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-once-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeShortVideo(at: url)
        let observer = VideoPlayerObserver()
        observer.setPlayer(url: url, isGIF: true, shouldLoop: false)
        defer { observer.tearDown() }
        let player = try XCTUnwrap(observer.getPlayer())
        let item = try XCTUnwrap(player.currentItem)
        let firstEnd = XCTestExpectation(description: "The observer stopped after the first pass")
        let firstPass = observer.$didReachEnd.first(where: { $0 }).sink { _ in firstEnd.fulfill() }
        defer { firstPass.cancel() }
        observer.play()
        await fulfillment(of: [firstEnd], timeout: 90)
        XCTAssertTrue(observer.didReachEnd)
        XCTAssertTrue(observer.hasPlayedToEnd)
        XCTAssertFalse(observer.isPlaybackRequested)
        XCTAssertFalse(observer.isPlaybackActive)
        let end = player.currentTime()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(player.currentTime(), end, "A manual GIF must stay stopped after its first pass")
        // Record the seek and the second complete pass even if the short clip finishes
        // before the test next gets to read the player's current time.
        let rewind = XCTNSNotificationExpectation(name: .AVPlayerItemTimeJumped, object: item)
        let replayEnd = XCTNSNotificationExpectation(name: .AVPlayerItemDidPlayToEndTime, object: item)
        observer.play()
        XCTAssertFalse(observer.didReachEnd)
        XCTAssertTrue(observer.isPlaybackRequested)
        await fulfillment(of: [rewind, replayEnd], timeout: 90)
    }

    func testLocalGIFVideoContinuesThroughFourLoopBoundaries() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-loop-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeShortVideo(at: url)
        let observer = VideoPlayerObserver()
        observer.setPlayer(url: url, isGIF: true)
        defer { observer.tearDown() }
        // AVPlayerLooper plays replicas of the template item. Each replica posts its
        // own end notification even when the main actor is too busy to sample a rewind.
        let loops = XCTestExpectation(description: "Four completed passes of the test clip")
        loops.expectedFulfillmentCount = 4
        let ends = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .filter { notification in
                guard let item = notification.object as? AVPlayerItem else { return false }
                return (item.asset as? AVURLAsset)?.url == url
            }
            .prefix(4)
            .sink { _ in loops.fulfill() }
        defer { ends.cancel() }
        observer.play()
        XCTAssertTrue(observer.isPlaybackActive)
        await fulfillment(of: [loops], timeout: 90)
        XCTAssertTrue(observer.isPlaybackActive)
        XCTAssertFalse(observer.didFail)
    }

    private func makeShortVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<5 {
            let deadline = ContinuousClock.now + .seconds(15)
            while !input.isReadyForMoreMediaData, writer.status == .writing, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard input.isReadyForMoreMediaData else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            let result = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB,
                nil, &buffer)
            XCTAssertEqual(result, kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
            address.assumingMemoryBound(to: UInt32.self).initialize(
                repeating: frame.isMultiple(of: 2) ? 0xFF00FF00 : 0xFFFF0000,
                count: CVPixelBufferGetBytesPerRow(pixels) * 64 / MemoryLayout<UInt32>.stride)
            CVPixelBufferUnlockBaseAddress(pixels, [])
            guard adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
