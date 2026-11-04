import AVFoundation
import CoreVideo
import Foundation
import Testing
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
        observer.play()
        await Task.yield()
        #expect(!observer.didReachEnd)
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
        let deadline = ContinuousClock.now + .seconds(6)
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
        try await Task.sleep(for: .milliseconds(100))
        #expect(!observer.didReachEnd)
        #expect(player.currentTime() < end)
    }

    @Test func aLocalGIFVideoContinuesThroughFourLoopBoundaries() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-loop-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeShortVideo(at: url)
        let observer = VideoPlayerObserver()
        observer.setPlayer(url: url, isGIF: true)
        defer { observer.tearDown() }
        let player = try #require(observer.getPlayer())
        observer.play()
        let deadline = ContinuousClock.now + .seconds(8)
        var previousTime = 0.0
        var loops = 0
        while loops < 4, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            let time = player.currentTime().seconds
            if time < previousTime - 0.1 { loops += 1 }
            previousTime = time
            #expect(observer.isPlaybackActive)
            #expect(!observer.didFail)
        }
        #expect(loops >= 4, "The player must actually advance through loops, not just keep its play icon hidden")
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
            let deadline = ContinuousClock.now + .seconds(4)
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
