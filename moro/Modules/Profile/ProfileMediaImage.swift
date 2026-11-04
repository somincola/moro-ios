import Combine
import SwiftUI

struct ProfileMediaAnimationPolicy {
    var autoplayGIFs: Bool
    var playAnimatedImages: Bool
    var reduceMotion: Bool
    var isLowPowerMode: Bool

    var allowsAnimation: Bool {
        autoplayGIFs && playAnimatedImages && !reduceMotion && !isLowPowerMode
    }
}

/// Profile identity media retains its small set of providers when paused. Timeline avatars
/// use a separate bounded pool; inline emoji keep their static renderers.
struct ProfileMediaImage: View {
    let url: URL
    let staticURL: URL?
    let thumbnailPixelSize: CGFloat
    var isVisible = true
    var maximumAnimatedBufferSize: UInt = 8 * 1024 * 1024

    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isMounted = false
    @State private var usesStaticFallback = false
    @State private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var allowsAnimation: Bool {
        ProfileMediaAnimationPolicy(
            autoplayGIFs: mediaPrefs.autoplayGIFs, playAnimatedImages: playAnimatedImages,
            reduceMotion: reduceMotion, isLowPowerMode: isLowPowerMode
        ).allowsAnimation && !usesStaticFallback
    }

    private var fallbackURL: URL {
        guard let staticURL, let scheme = staticURL.scheme?.lowercased(),
              ["https", "http"].contains(scheme), staticURL.host != nil else { return url }
        return staticURL
    }

    var body: some View {
        SDWebRemoteImage(
            url: allowsAnimation ? url : fallbackURL,
            thumbnailPixelSize: thumbnailPixelSize,
            allowsAnimation: allowsAnimation,
            isAnimationPlaybackActive: isMounted && isVisible && scenePhase == .active,
            animationLoadingMode: .boundedPreview,
            maximumAnimatedBufferSize: maximumAnimatedBufferSize,
            onLoadFailure: {
                guard allowsAnimation, let staticURL, staticURL != url else { return }
                usesStaticFallback = true
            }
        )
        .onAppear { isMounted = true }
        .onDisappear { isMounted = false }
        .onChange(of: url) { _, _ in usesStaticFallback = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
