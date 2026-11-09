import SDWebImage
import SwiftUI

/// Original GIF attachments share the GIFV viewport policy and play once per manual request.
struct InlineGIFImageView: View {
    let attachment: Status.Attachment
    let contentMode: ContentMode
    let isConcealed: Bool
    @Environment(\.moroMediaPrefs) private var preferences
    @Environment(\.moroPlaybackScope) private var scope
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @State private var isVisible = false
    @State private var playRequested = false
    @State private var requestID = UUID()
    @State private var didFail = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private let presentation = MediaPlaybackPresentation.shared

    private var autoplays: Bool {
        preferences.autoplayGIFs && playAnimatedImages && !reduceMotion && !isLowPower
    }
    private var eligible: Bool {
        MediaPlaybackPolicy.canPlay(isVisible: isVisible, isActive: scope.isActive,
            isSceneActive: scenePhase == .active, isCovered: presentation.coversInlinePlayback,
            isConcealed: isConcealed)
    }
    private var plays: Bool { eligible && !didFail && (autoplays || playRequested) }

    var body: some View {
        ZStack {
            SDWebRemoteImage(url: attachment.previewURL ?? attachment.url, thumbnailPixelSize: 2000,
                contentMode: contentMode == .fit ? .scaleAspectFit : .scaleAspectFill, allowsAnimation: false)
            InlineGIFSurface(url: attachment.url, contentMode: contentMode,
                eligible: eligible, plays: plays, loops: autoplays, requestID: requestID,
                onFinished: { playRequested = false }, onFailure: { didFail = true })
            if !isConcealed, !plays {
                Button {
                    requestID = UUID()
                    didFail = false
                    playRequested = true
                } label: {
                    Image(systemName: didFail ? "arrow.clockwise.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.A11y.play)
                .accessibilityIdentifier("media.play.\(attachment.id)")
            }
        }
        .onScrollVisibilityChange(threshold: MediaPlaybackPolicy.visibleFraction) { isVisible = $0 }
        .onChange(of: eligible) { _, eligible in if !eligible { playRequested = false } }
        .onChange(of: presentation.coversInlinePlayback) { _, covered in
            if covered { playRequested = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onDisappear { isVisible = false; playRequested = false }
    }
}

private struct InlineGIFSurface: UIViewRepresentable {
    let url: URL
    let contentMode: ContentMode
    let eligible: Bool
    let plays: Bool
    let loops: Bool
    let requestID: UUID
    let onFinished: () -> Void
    let onFailure: () -> Void

    func makeUIView(context: Context) -> InlineGIFSurfaceView { InlineGIFSurfaceView(frame: .zero) }
    func updateUIView(_ view: InlineGIFSurfaceView, context: Context) {
        view.contentMode = contentMode == .fit ? .scaleAspectFit : .scaleAspectFill
        view.onFinished = onFinished
        view.onFailure = onFailure
        view.configure(url: url, eligible: eligible, plays: plays, loops: loops, requestID: requestID)
    }
    static func dismantleUIView(_ view: InlineGIFSurfaceView, coordinator: ()) { view.releaseAnimation() }
}

final class InlineGIFSurfaceView: SDAnimatedImageView {
    // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
    nonisolated deinit {}

    var onFinished: (() -> Void)?
    var onFailure: (() -> Void)?
    private var sourceURL: URL?
    private var operation: SDWebImageOperation?
    private var generation = UUID()
    private var requestID: UUID?
    private var wantsPlayback = false
    private var loops = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        autoPlayAnimatedImage = false
        maxBufferSize = 8 * 1024 * 1024
        clearBufferWhenStopped = false
        resetFrameIndexWhenStopped = false
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(url: URL, eligible: Bool, plays: Bool, loops: Bool, requestID: UUID) {
        if sourceURL != url { releaseAnimation(); sourceURL = url }
        wantsPlayback = plays
        let resets = self.requestID != requestID || self.loops != loops
        self.requestID = requestID
        self.loops = loops
        guard eligible else { releaseAnimation(); return }
        if resets, let image { install(image) }
        if image == nil, operation == nil, plays {
            let generation = UUID()
            self.generation = generation
            operation = SDWebImageManager.shared.loadImage(with: url,
                options: [.retryFailed, .matchAnimatedImageClass],
                context: [.animatedImageClass: SDAnimatedImage.self, .imageScaleDownLimitBytes: 8 * 1024 * 1024],
                progress: nil) { [weak self] image, _, _, _, finished, _ in
                    guard finished else { return }
                    DispatchQueue.main.async {
                        guard let self, self.generation == generation else { return }
                        self.operation = nil
                        guard let image else { self.onFailure?(); return }
                        self.install(image)
                    }
                }
        }
        if plays { startAnimating() } else { stopAnimating() }
    }

    private func install(_ image: UIImage) {
        self.image = nil
        shouldCustomLoopCount = !loops
        animationRepeatCount = 1
        self.image = image
        if !loops, let player {
            let original = player.animationLoopHandler
            let request = requestID
            player.animationLoopHandler = { [weak self] count in
                original?(count)
                guard count >= 1 else { return }
                DispatchQueue.main.async {
                    guard let self, self.requestID == request, !self.loops else { return }
                    self.onFinished?()
                }
            }
        }
        if wantsPlayback { startAnimating() }
    }

    func releaseAnimation() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        stopAnimating()
        image = nil
    }
}
