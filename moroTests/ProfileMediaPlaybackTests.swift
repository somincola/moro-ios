import Combine
import SDWebImage
import SwiftUI
import Testing
import UIKit
@testable import moro

@MainActor
struct ProfileMediaPlaybackTests {
    @Test func anUnusableAnimatedResourceFallsBackToTheStaticAvatar() async throws {
        let (window, _) = makeHost(failingOriginal: true)
        defer { window.isHidden = true }
        let view = try await imageView(in: window)
        #expect(view.image != nil)
        #expect(!(view.image is SDAnimatedImage))
        #expect(!view.isAnimating)
    }

    @Test func anAnimatedAvatarKeepsPlayingWhenTheViewerZooms() async throws {
        let controller = UIViewController()
        let page = ImagePreviewPageView(frame: CGRect(x: 0, y: 0, width: 240, height: 480))
        controller.view = page
        let window = UIWindow(frame: page.frame)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        page.layoutIfNeeded()
        let image = try #require(SDAnimatedImage(data: ProfileMediaFixture.gifData()))
        let scroll = page.scrollView
        scroll.display(image)
        scroll.layoutIfNeeded()
        try await waitUntil { scroll.imageView.isAnimating }
        let width = scroll.imageView.frame.width
        scroll.toggleZoom(at: CGPoint(x: 40, y: 40), animated: false)
        #expect(scroll.imageView.frame.width > width)
        let firstFrame = scroll.imageView.currentFrameIndex
        try await waitUntil { scroll.imageView.currentFrameIndex != firstFrame }
        scroll.isAnimationPlaybackActive = false
        #expect(!scroll.imageView.isAnimating)
        #expect(scroll.imageView.image === image)
    }

    @Test func profileAnimationPausesWithoutReplacingItsDecodedImage() async throws {
        let (window, state) = makeHost()
        defer { window.isHidden = true }
        let view = try await imageView(in: window)
        try await waitUntil { view.isAnimating }
        let decodedImage = try #require(view.image as? SDAnimatedImage)
        #expect(decodedImage.animatedImageFrameCount == 2)
        #expect(view.maxBufferSize == 2 * 1024 * 1024)
        let firstFrame = view.currentFrameIndex
        try await waitUntil { view.currentFrameIndex != firstFrame }

        state.isVisible = false
        try await waitUntil { !view.isAnimating }
        #expect(view.image === decodedImage)
        state.isVisible = true
        try await waitUntil { view.isAnimating }
        #expect(view.image === decodedImage)

        state.scenePhase = .background
        try await waitUntil { !view.isAnimating }
        state.scenePhase = .active
        try await waitUntil { view.isAnimating }
        #expect(view.image === decodedImage)
    }

    @Test func disablingAutoplayShowsAStaticAvatar() async throws {
        let (window, state) = makeHost()
        defer { window.isHidden = true }
        let view = try await imageView(in: window)
        try await waitUntil { view.isAnimating }
        state.autoplayGIFs = false
        try await waitUntil { !view.isAnimating && !(view.image is SDAnimatedImage) }
        state.autoplayGIFs = true
        try await waitUntil { view.isAnimating }
    }

    @Test func systemAndPowerPreferencesCanEachDisableDecorativeAnimation() {
        #expect(ProfileMediaAnimationPolicy(autoplayGIFs: true, playAnimatedImages: true,
            reduceMotion: false, isLowPowerMode: false).allowsAnimation)
        for policy in [
            ProfileMediaAnimationPolicy(autoplayGIFs: false, playAnimatedImages: true,
                reduceMotion: false, isLowPowerMode: false),
            ProfileMediaAnimationPolicy(autoplayGIFs: true, playAnimatedImages: false,
                reduceMotion: false, isLowPowerMode: false),
            ProfileMediaAnimationPolicy(autoplayGIFs: true, playAnimatedImages: true,
                reduceMotion: true, isLowPowerMode: false),
            ProfileMediaAnimationPolicy(autoplayGIFs: true, playAnimatedImages: true,
                reduceMotion: false, isLowPowerMode: true),
        ] {
            #expect(!policy.allowsAnimation)
        }
    }

    private func makeHost(failingOriginal: Bool = false) -> (UIWindow, PlaybackState) {
        let state = PlaybackState(url: failingOriginal ? URL(string: "unsupported-profile-media://avatar.gif") : nil)
        let data = ProfileMediaFixture.gifData()
        let image = SDAnimatedImage(data: data)!
        if !failingOriginal {
            SDImageCache.shared.store(image, imageData: data, forKey: state.url.absoluteString, toDisk: true)
        }
        let context: [SDWebImageContextOption: Any] = [
            .imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: 80, height: 80))
        ]
        let key = SDWebImageManager.shared.cacheKey(for: state.staticURL, context: context)!
        // Memory-pressure tests run concurrently in other suites. Keep the fixture available
        // on disk so a cache purge never turns this offline fallback test into a network call.
        SDImageCache.shared.store(UIImage(cgImage: image.cgImage!), forKey: key, toDisk: true)
        let host = UIHostingController(rootView: PlaybackHost(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        return (window, state)
    }

    private func imageView(in window: UIWindow) async throws -> SDAnimatedImageView {
        func find(_ view: UIView) -> SDAnimatedImageView? {
            if let view = view as? SDAnimatedImageView { return view }
            return view.subviews.lazy.compactMap(find).first
        }
        try await waitUntil { find(window)?.image != nil }
        return try #require(find(window))
    }

    /// Returns as soon as the condition holds; the deadline is only for a stuck load. Decoding
    /// on CI's busy runner (parallel suites, few cores) took about 12 s, so leave plenty.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition())
    }
}

@MainActor
private final class PlaybackState: ObservableObject {
    let url: URL
    let staticURL = URL(string: "https://profile-media-test.invalid/\(UUID().uuidString).png")!
    @Published var isVisible = true
    @Published var autoplayGIFs = true
    @Published var scenePhase = ScenePhase.active

    init(url: URL? = nil) {
        self.url = url ?? URL(string: "https://profile-media-test.invalid/\(UUID().uuidString).gif")!
    }
}

private struct PlaybackHost: View {
    @ObservedObject var state: PlaybackState

    var body: some View {
        ProfileMediaImage(url: state.url, staticURL: state.staticURL, thumbnailPixelSize: 80,
            isVisible: state.isVisible, maximumAnimatedBufferSize: 2 * 1024 * 1024)
            .frame(width: 80, height: 80)
            .environment(\.moroMediaPrefs, MoroMediaPreferences(autoplayGIFs: state.autoplayGIFs))
            .environment(\.scenePhase, state.scenePhase)
    }
}
