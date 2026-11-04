import SDWebImage
import SwiftUI

struct TimelineAnimatedAvatar: View {
    let url: URL
    let size: CGFloat
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Environment(\.moroPlaybackScope) private var scope
    @Environment(\.moroUIKitScrollVisibility) private var uiKitVisibility
    @Environment(\.activeAccountKey) private var accountKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @State private var isVisible = false
    @State private var isSettled = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private let presentation = MediaPlaybackPresentation.shared

    private var policyAllowsAnimation: Bool {
        scope.allowsAnimatedAvatars && scope.systemAllowsAnimatedAvatars
            && mediaPrefs.autoplayGIFs && playAnimatedImages && !reduceMotion && !isLowPower
    }
    private var canRetain: Bool {
        policyAllowsAnimation && MediaPlaybackPolicy.canPlay(isVisible: isVisible, isActive: scope.isActive,
                isSceneActive: scenePhase == .active, isCovered: presentation.coversInlinePlayback)
    }
    private var canSettle: Bool { canRetain && !scope.isScrolling }

    var body: some View {
        AvatarAnimationSurface(url: url,
            pixelSize: AvatarAnimationLimits.pixelSize(for: size, scale: displayScale),
            retainsAnimation: canRetain, playsAnimation: canSettle && isSettled)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                if let uiKitVisibility {
                    UIKitScrollVisibilityProbe(visibility: uiKitVisibility) { isVisible = $0 }
                }
            }
            .onScrollVisibilityChange(threshold: MediaPlaybackPolicy.visibleFraction) {
                if uiKitVisibility == nil { isVisible = $0 }
            }
            .task(id: SettleKey(url: url, account: accountKey, allowed: canSettle,
                recovery: TimelineAvatarAnimationPool.shared.recovery.revision)) {
                isSettled = false
                guard canSettle else { return }
                try? await Task.sleep(for: MediaPlaybackPolicy.settleDelay)
                guard !Task.isCancelled else { return }
                isSettled = true
            }
            .onChange(of: policyAllowsAnimation) { _, enabled in
                if !enabled { TimelineAvatarAnimationPool.shared.removeAll() }
            }
            .onChange(of: accountKey, initial: true) { _, key in
                TimelineAvatarAnimationPool.shared.noteAccount(key)
            }
            // The pool itself empties on Low Power Mode; each avatar only stops asking.
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onDisappear { isVisible = false }
    }

    private struct SettleKey: Hashable {
        let url: URL
        let account: String?
        let allowed: Bool
        let recovery: UInt
    }
}

struct AvatarAnimationSurface: UIViewRepresentable {
    let url: URL
    let pixelSize: Int
    let retainsAnimation: Bool
    let playsAnimation: Bool

    func makeUIView(context: Context) -> AvatarAnimationSurfaceView { AvatarAnimationSurfaceView() }
    func updateUIView(_ view: AvatarAnimationSurfaceView, context: Context) {
        view.configure(key: .init(url: url, pixelSize: pixelSize), retain: retainsAnimation, play: playsAnimation)
    }
    static func dismantleUIView(_ view: AvatarAnimationSurfaceView, coordinator: ()) { view.releaseAnimation() }
}

final class AvatarAnimationSurfaceView: UIView {
    let imageView = SDAnimatedImageView()
    private let pool: TimelineAvatarAnimationPool
    private var key: TimelineAvatarAnimationPool.Key?
    private var consumerID: UUID?
    private var wantsPlayback = false

    init(pool: TimelineAvatarAnimationPool? = nil) {
        self.pool = pool ?? .shared
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFill
        imageView.autoPlayAnimatedImage = false
        imageView.maxBufferSize = AvatarAnimationLimits.frameBufferBytes
        // The library may share a frame pool for the provider. Detaching the last player
        // disposes that pool; one disappearing avatar must not clear another one's frames.
        imageView.clearBufferWhenStopped = false
        imageView.resetFrameIndexWhenStopped = false
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); imageView.frame = bounds }

    func configure(key: TimelineAvatarAnimationPool.Key, retain: Bool, play: Bool) {
        if self.key != key { releaseAnimation(); self.key = key }
        wantsPlayback = play
        guard retain else { releaseAnimation(); return }
        if consumerID == nil, play {
            let id = UUID()
            consumerID = id
            let acquired = pool.acquire(key, consumerID: id, ready: { [weak self] image in
                guard let self, self.consumerID == id, self.key == key else { return }
                self.imageView.image = image
                self.updatePlayback()
            }, invalidate: { [weak self] in
                guard let self, self.consumerID == id else { return }
                self.consumerID = nil
                self.imageView.stopAnimating()
                self.imageView.image = nil
            })
            if !acquired { consumerID = nil }
        }
        updatePlayback()
    }

    func releaseAnimation() {
        let id = consumerID
        consumerID = nil
        imageView.stopAnimating()
        imageView.image = nil
        if let key, let id { pool.release(key, consumerID: id) }
    }

    private func updatePlayback() {
        if wantsPlayback { imageView.startAnimating() }
        else { imageView.stopAnimating() }
    }

    nonisolated deinit {
        if let key, let consumerID {
            let pool = pool
            Task { @MainActor in pool.release(key, consumerID: consumerID) }
        }
    }
}
