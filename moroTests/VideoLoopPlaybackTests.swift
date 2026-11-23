import AVFoundation
import Combine
import CoreVideo
import Foundation
import Testing
import XCTest
@testable import moro

@MainActor
struct VideoLoopPlaybackTests {
    @Test func aQueuedEndCallbackCannotStopANewLeaseOfTheSamePlayer() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-generation-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeShortVideo(at: url)
        let pool = TimelineVideoPlayerPool()
        let observer = VideoPlayerObserver(pool: pool)
        defer { observer.tearDown(); pool.removeAll() }
        observer.setPlayer(url: url, isGIF: true, shouldLoop: false)
        let player = try #require(observer.getPlayer())
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
        observer.tearDown()
        observer.setPlayer(url: url, isGIF: true, shouldLoop: false)
        #expect(observer.getPlayer() === player)
        // Let the queued callback run before anything plays: the clip is half a second long,
        // so once it plays a slow runner can genuinely reach its end before the check.
        try await Task.sleep(for: .milliseconds(200))
        #expect(!observer.didReachEnd)
        observer.play()
        #expect(observer.isPlaybackRequested)
    }

    @Test func aManuallyStartedGIFVideoPlaysOnceAndCanBeReplayed() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-once-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeShortVideo(at: url)
        let observer = VideoPlayerObserver()
        observer.setPlayer(url: url, isGIF: true, shouldLoop: false)
        defer { observer.tearDown() }
        let player = try #require(observer.getPlayer())
        observer.play()
        let deadline = ContinuousClock.now + .seconds(30)
        while !observer.didReachEnd, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(observer.didReachEnd)
        #expect(observer.hasPlayedToEnd)
        #expect(!observer.isPlaybackRequested)
        #expect(!observer.isPlaybackActive)
        let end = player.currentTime()
        try await Task.sleep(for: .milliseconds(600))
        #expect(player.currentTime() == end, "A manual GIF must stay stopped after its first pass")
        observer.play()
        #expect(!observer.didReachEnd)
        #expect(observer.isPlaybackRequested)
        // Replay rewinds to the start. Watch for the rewind rather than checking after a fixed
        // pause: on a busy runner the half-second clip can play through again within it.
        let rewindDeadline = ContinuousClock.now + .seconds(15)
        var rewound = false
        while !rewound, ContinuousClock.now < rewindDeadline {
            rewound = player.currentTime() < end
            if !rewound { try await Task.sleep(for: .milliseconds(5)) }
        }
        #expect(rewound, "Replaying a GIF that played through starts it over")
    }

    @Test func aLocalGIFVideoContinuesThroughFourLoopBoundaries() async throws {
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
        #expect(observer.isPlaybackActive)
        let result = await XCTWaiter.fulfillment(of: [loops], timeout: 90)
        #expect(result == .completed, "The local GIF video must finish four passes")
        #expect(observer.isPlaybackActive)
        #expect(!observer.didFail)
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
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<5 {
            let deadline = ContinuousClock.now + .seconds(15)
            while !input.isReadyForMoreMediaData, writer.status == .writing, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(input.isReadyForMoreMediaData)
            var buffer: CVPixelBuffer?
            let result = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB,
                nil, &buffer)
            try #require(result == kCVReturnSuccess)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let address = try #require(CVPixelBufferGetBaseAddress(pixels))
            address.assumingMemoryBound(to: UInt32.self).initialize(
                repeating: frame.isMultiple(of: 2) ? 0xFF00FF00 : 0xFFFF0000,
                count: CVPixelBufferGetBytesPerRow(pixels) * 64 / MemoryLayout<UInt32>.stride)
            CVPixelBufferUnlockBaseAddress(pixels, [])
            try #require(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}
