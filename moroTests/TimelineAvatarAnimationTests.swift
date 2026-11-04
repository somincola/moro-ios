import ImageIO
import SDWebImage
import SwiftUI
import Testing
import UIKit
@testable import moro

@MainActor @Suite(.serialized)
struct TimelineAvatarAnimationTests {
    @Test func allFramesStayAnimatedAndDecodeAtTheAvatarPixelSize() async throws {
        let data = ProfileMediaFixture.gifData(size: CGSize(width: 400, height: 400))
        let prepared = try #require(await AvatarAnimationDecoder.shared.prepare(data, pixelSize: 96))
        #expect(prepared.image.animatedImageFrameCount == 2)
        for index in 0..<prepared.image.animatedImageFrameCount {
            let frame = try #require(prepared.image.animatedImageFrame(at: index)?.cgImage)
            #expect(frame.width <= 96)
            #expect(frame.height <= 96)
        }
        #expect(!prepared.image.isAllFramesLoaded)
    }

    @Test func oversizedAndInvalidInputsKeepTheStaticAvatar() async {
        let large = ProfileMediaFixture.gifData(size: CGSize(width: 1025, height: 10))
        #expect(await AvatarAnimationDecoder.shared.prepare(large, pixelSize: 160) == nil)
        #expect(await AvatarAnimationDecoder.shared.prepare(Data([1, 2, 3]), pixelSize: 160) == nil)
        #expect(await AvatarAnimationDecoder.shared.prepare(
            Data(repeating: 0, count: AvatarAnimationLimits.maximumFileBytes + 1), pixelSize: 160) == nil)
        var largerLogicalScreen = ProfileMediaFixture.gifData()
        largerLogicalScreen[6] = 1
        largerLogicalScreen[7] = 4 // 1025px logical canvas, even though individual frames are small.
        #expect(await AvatarAnimationDecoder.shared.prepare(largerLogicalScreen, pixelSize: 160) == nil)
    }

    @Test func duplicateAvatarsShareOneDecoderAndOneViewLeavingDoesNotEvictTheOther() async throws {
        let data = ProfileMediaFixture.gifData()
        let counter = AvatarLoadCounter(data: data)
        let pool = TimelineAvatarAnimationPool(observesLifecycle: false, loader: { await counter.load($0) })
        let key = key("duplicate")
        let first = UUID(), second = UUID()
        var images: [SDAnimatedImage] = []
        #expect(pool.acquire(key, consumerID: first, ready: { images.append($0) }, invalidate: {}))
        #expect(pool.acquire(key, consumerID: second, ready: { images.append($0) }, invalidate: {}))
        try await wait { images.count == 2 }
        #expect(images[0] === images[1])
        #expect(await counter.count == 1)
        pool.release(key, consumerID: first)
        #expect(pool.activeCount == 1)
        #expect(pool.warmCount == 0)
        pool.release(key, consumerID: second)
        #expect(pool.activeCount == 0)
        #expect(pool.warmCount == 1)
        pool.removeAll()
    }

    @Test func aVisibleAvatarKeepsAdvancingWhenItsDuplicateLeavesAndPausesWhileScrolling() async throws {
        let data = ProfileMediaFixture.gifData(frameDuration: 0.1)
        let pool = TimelineAvatarAnimationPool(observesLifecycle: false, loader: { _ in data })
        let first = AvatarAnimationSurfaceView(pool: pool)
        let second = AvatarAnimationSurfaceView(pool: pool)
        let controller = UIViewController()
        controller.view.addSubview(first)
        controller.view.addSubview(second)
        first.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        second.frame = CGRect(x: 50, y: 0, width: 44, height: 44)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; first.releaseAnimation(); second.releaseAnimation(); pool.removeAll() }
        let resource = key("live-duplicate")
        first.configure(key: resource, retain: true, play: true)
        second.configure(key: resource, retain: true, play: true)
        try await wait { second.imageView.isAnimating }
        let index = second.imageView.currentFrameIndex
        first.releaseAnimation()
        try await wait { second.imageView.currentFrameIndex != index }
        second.configure(key: resource, retain: true, play: false)
        let pausedFrame = second.imageView.currentFrameIndex
        try await Task.sleep(for: .milliseconds(350))
        #expect(!second.imageView.isAnimating)
        #expect(second.imageView.currentFrameIndex == pausedFrame)
    }

    @Test func anOriginalGIFActuallyFinishesOneLoopAndCanReplayWithoutReparsing() async throws {
        let data = ProfileMediaFixture.gifData(frameDuration: 0.2)
        let url = URL(string: "https://original-gif-fixture.invalid/\(UUID()).gif")!
        let image = try #require(SDAnimatedImage(data: data))
        await SDImageCache.shared.store(image, imageData: data, forKey: url.absoluteString, toDisk: true)
        let view = InlineGIFSurfaceView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        let controller = UIViewController()
        controller.view.addSubview(view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; view.releaseAnimation() }
        var completions = 0
        view.onFinished = { completions += 1 }
        view.configure(url: url, eligible: true, plays: true, loops: false, requestID: UUID())
        try await wait { view.currentFrameIndex == 1 }
        try await wait { completions == 1 }
        #expect(!view.isAnimating)
        try await Task.sleep(for: .milliseconds(500))
        #expect(completions == 1)
        let provider = view.image
        view.configure(url: url, eligible: true, plays: true, loops: false, requestID: UUID())
        try await wait { completions == 2 }
        #expect(view.image === provider)
        #expect(!view.isAnimating)
    }

    @Test func warmHitAvoidsReparsingAndExpiryReleasesTheProvider() async throws {
        let data = ProfileMediaFixture.gifData()
        let counter = AvatarLoadCounter(data: data)
        let pool = TimelineAvatarAnimationPool(warmLifetime: 0.08, observesLifecycle: false,
            loader: { await counter.load($0) })
        let key = key("warm")
        let first = AvatarAnimationSurfaceView(pool: pool)
        first.configure(key: key, retain: true, play: true)
        try await wait { first.imageView.image != nil }
        let provider = WeakAvatarImage(first.imageView.image)
        first.releaseAnimation()
        #expect(first.imageView.image == nil)
        #expect(pool.warmCount == 1)
        let second = AvatarAnimationSurfaceView(pool: pool)
        second.configure(key: key, retain: true, play: true)
        #expect(second.imageView.image === provider.image)
        #expect(await counter.count == 1)
        // An old expiry must not remove a resource that is visible again.
        try await Task.sleep(for: .milliseconds(150))
        #expect(pool.activeCount == 1)
        #expect(second.imageView.image != nil)
        second.releaseAnimation()
        try await wait { pool.warmCount == 0 && provider.image == nil }
    }

    @Test func pendingWorkIsBoundedAndLateCompletionsCannotReattachOffscreenAvatars() async throws {
        let data = ProfileMediaFixture.gifData()
        let pool = TimelineAvatarAnimationPool(observesLifecycle: false, loader: { _ in
            // Deliberately ignores cancellation to exercise the generation guard.
            try? await Task.sleep(for: .milliseconds(40))
            return data
        })
        var ready = 0
        let ids = (0..<9).map { _ in UUID() }
        for index in 0..<9 {
            let acquired = pool.acquire(key("pending-\(index)"), consumerID: ids[index],
                ready: { _ in ready += 1 }, invalidate: {})
            #expect(acquired == (index < 8))
        }
        #expect(pool.activeCount == 8)
        #expect(pool.reservedFrameBytes <= AvatarAnimationLimits.frameBudget)
        pool.removeAll()
        try await Task.sleep(for: .milliseconds(100))
        #expect(ready == 0)
        #expect(pool.activeCount == 0)
        #expect(pool.warmCount == 0)
    }

    @Test func warmCacheEvictsOldEntriesAndPressureClearsVisibleViews() async throws {
        let data = ProfileMediaFixture.gifData()
        let pool = TimelineAvatarAnimationPool(warmLimit: 2, observesLifecycle: false, loader: { _ in data })
        for index in 0..<4 {
            let view = AvatarAnimationSurfaceView(pool: pool)
            view.configure(key: key("lru-\(index)"), retain: true, play: true)
            try await wait { view.imageView.image != nil }
            view.releaseAnimation()
            #expect(pool.warmCount <= 2)
        }
        let visible = AvatarAnimationSurfaceView(pool: pool)
        visible.configure(key: key("visible"), retain: true, play: true)
        try await wait { visible.imageView.image != nil }
        #expect(visible.imageView.maxBufferSize == AvatarAnimationLimits.frameBufferBytes)
        pool.removeAll(cooldown: 30)
        #expect(visible.imageView.image == nil)
        #expect(pool.activeCount == 0 && pool.warmCount == 0)
        #expect(!pool.acquire(key("pressure"), consumerID: UUID(), ready: { _ in }, invalidate: {}))
    }

    @Test func allMediaShareVisibilityAndPresentationOwnershipRules() {
        #expect(MediaPlaybackPolicy.visibleFraction == VideoPlayerView.visibleFraction)
        #expect(!MediaPlaybackPolicy.canPlay(isVisible: false, isActive: true, isSceneActive: true, isCovered: false))
        #expect(!MediaPlaybackPolicy.canPlay(isVisible: true, isActive: false, isSceneActive: true, isCovered: false))
        let focus = MediaPlaybackPresentation()
        let first = focus.begin(), second = focus.begin()
        focus.end(first)
        #expect(focus.coversInlinePlayback)
        focus.end(second)
        #expect(!focus.coversInlinePlayback)
    }

    @Test func browsingOneThousandDifferentAvatarsKeepsOnlyTwoWarmDecoders() async throws {
        let data = ProfileMediaFixture.gifData()
        let pool = TimelineAvatarAnimationPool(observesLifecycle: false, loader: { _ in data })
        let view = AvatarAnimationSurfaceView(pool: pool)
        for index in 0..<1000 {
            view.configure(key: key("stress-\(index)"), retain: true, play: true)
            try await wait { view.imageView.image != nil }
            view.releaseAnimation()
            #expect(pool.activeCount == 0)
            #expect(pool.warmCount <= 2)
            #expect(pool.encodedBytes <= AvatarAnimationLimits.dataBudget)
        }
        pool.removeAll()
        #expect(pool.warmCount == 0 && pool.encodedBytes == 0)
    }

    @Test func retainedTimelinePagesOnlyGrantPlaybackToThePresentedActivePage() {
        let bridge = TimelineScrollBridge()
        let home = bridge.playbackScope(for: .home)
        let local = bridge.playbackScope(for: .local)
        bridge.setActive(true)
        #expect(home.allowsAnimatedAvatars)
        #expect(!MediaPlaybackScope.unrestricted.allowsAnimatedAvatars)
        #expect(home.isActive && !local.isActive)
        bridge.updatePhase(.interacting, for: .home)
        #expect(home.isScrolling)
        let transaction = bridge.beginPresentation(for: .local)
        #expect(!home.isActive && !local.isActive)
        #expect(bridge.finishPresentation(transaction))
        #expect(!home.isActive && local.isActive)
        bridge.setActive(false)
        #expect(!home.isActive && !local.isActive)
    }

    private func key(_ name: String) -> TimelineAvatarAnimationPool.Key {
        .init(url: URL(string: "https://avatar-fixture.invalid/\(name).gif")!, pixelSize: 96)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}

private actor AvatarLoadCounter {
    let data: Data
    var count = 0
    init(data: Data) { self.data = data }
    func load(_ url: URL) -> Data { count += 1; return data }
}

@MainActor private final class WeakAvatarImage {
    weak var image: UIImage?
    init(_ image: UIImage?) { self.image = image }
}

/// Every avatar on screen reacts to the same setting, power or account change. The pool
/// must do the work once, not once per avatar.
@MainActor
struct TimelineAvatarAnimationPoolResetTests {
    @Test func repeatedResetsAndTheSameAccountDoNothingOnceEmpty() {
        let pool = TimelineAvatarAnimationPool(observesLifecycle: false, loader: { _ in Data() })
        let start = pool.recovery.revision
        pool.removeAll()
        pool.removeAll()
        #expect(pool.recovery.revision == start, "An empty pool has nothing to recover")

        pool.noteAccount("account-a")
        pool.noteAccount("account-a")
        pool.noteAccount("account-a")
        #expect(pool.recovery.revision == start, "Reporting the same account is not a switch")

        pool.removeAll(cooldown: 1)
        #expect(pool.recovery.revision == start, "Memory pressure waits out its cooldown first")
    }
}
