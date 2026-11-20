import AVKit
import Combine
import SwiftUI

/// Presents the same player in an overlay so an interactive dismissal can reveal the source.
@MainActor
enum NativeVideoPlayer {
    @discardableResult
    static func present(attachment: Status.Attachment, post: MediaPreviewPost? = nil) -> Bool {
        guard let presenter = UIApplication.shared.moroTopViewController(),
              !(presenter is MediaPreviewHostingController) else { return false }
        if let docked = NativeVideoSession.docked {
            if docked.attachment.url == attachment.url, docked.post?.status.id == post?.status.id {
                docked.returnToFullscreen()
                return true
            }
            docked.end()
        }
        let session = NativeVideoSession(attachment: attachment, post: post)
        show(session, from: presenter)
        return true
    }

    static func show(_ session: NativeVideoSession, from presenter: UIViewController,
                     completion: (() -> Void)? = nil) {
        let controller = MediaPreviewHostingController(rootView: AnyView(EmptyView()))
        session.host = controller
        session.post?.closeBeforeAction = { [weak controller] action in controller?.close(completion: action) }
        controller.rootView = AnyView(VideoFullscreenView(session: session))
        controller.onClosed = { [weak session, weak controller] in
            if session?.host === controller { session?.leftFullscreen() }
        }
        controller.view.backgroundColor = .clear
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        controller.modalPresentationCapturesStatusBarAppearance = true
        presenter.present(controller, animated: !UIAccessibility.isReduceMotionEnabled, completion: completion)
    }
}

/// The playback lease belongs to this viewing session, including any time spent in system PiP.
@MainActor
final class NativeVideoSession: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    private(set) static var docked: NativeVideoSession?
    let attachment: Status.Attachment
    let post: MediaPreviewPost?
    let observer = VideoPlayerObserver(pool: .shared, continuesExistingPlayer: true)
    let layer = AVPlayerLayer()
    weak var host: MediaPreviewHostingController?
    var dismissRoute: (() -> Void)?

    @Published private(set) var canDock = false
    @Published private(set) var selectedRate: Float = 1
    @Published private(set) var isSpeedLocked = false
    @Published private(set) var isMuted: Bool
    @Published private(set) var pipFailed = false
    private var pip: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var playbackToken: UUID?
    private var started = false
    private var restored = false
    private var heldRate: Float?
    private var wasPlayingBeforeHold = false
    private var holdingSpeed = false
    private var holdsAudioFocus = false

    var player: AVPlayer? { observer.getPlayer() }
    var isGIF: Bool { attachment.type == "gifv" }

    init(attachment: Status.Attachment, post: MediaPreviewPost? = nil) {
        self.attachment = attachment
        self.post = post
        let gif = attachment.type == "gifv"
        isMuted = gif
        super.init()
        observer.setPlayer(url: attachment.url, isGIF: gif, shouldLoop: gif ? true : nil)
        playbackToken = MediaPlaybackPresentation.shared.begin()
        observer.setMuted(false)
        layer.player = player
        layer.videoGravity = .resizeAspect
        if !gif {
            holdsAudioFocus = true
            VideoAudioSession.beginAudiblePlayback()
            if AVPictureInPictureController.isPictureInPictureSupported() {
                pip = AVPictureInPictureController(playerLayer: layer)
                pip?.delegate = self
                pip?.canStartPictureInPictureAutomaticallyFromInline = true
                possibleObservation = pip?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
                    [weak self] _, change in
                    let possible = change.newValue == true
                    Task { @MainActor [weak self] in self?.canDock = possible }
                }
            }
        }
    }

    func startIfNeeded() {
        guard playbackToken != nil else { return }
        observer.setFullscreenLooping(true)
        guard !started else { return }
        started = true
        observer.play()
    }

    func togglePlayback() {
        if observer.isPlaybackActive { observer.pause() } else { observer.play() }
    }

    func toggleMute() {
        isMuted.toggle()
        observer.setMuted(isMuted)
    }

    func cycleRate() {
        let rates: [Float] = [1, 1.25, 1.5, 2]
        holdingSpeed = false
        isSpeedLocked = false
        heldRate = nil
        let next = ((rates.firstIndex(of: selectedRate) ?? 0) + 1) % rates.count
        setRate(rates[next])
    }

    private func setRate(_ rate: Float) {
        selectedRate = rate
        player?.defaultRate = rate
        if player?.timeControlStatus != .paused { player?.rate = rate }
    }

    func beginSpeedHold() {
        guard !holdingSpeed else { return }
        holdingSpeed = true
        guard !isSpeedLocked else { return }
        heldRate = selectedRate
        wasPlayingBeforeHold = observer.isPlaybackActive
        setRate(2)
        if !wasPlayingBeforeHold { observer.play() }
    }

    func finishSpeedHold(completedDrag: Bool) {
        guard holdingSpeed else { return }
        holdingSpeed = false
        if isSpeedLocked {
            if completedDrag { unlockSpeed() }
        } else if completedDrag {
            isSpeedLocked = true
        } else {
            if !wasPlayingBeforeHold { observer.pause() }
            setRate(heldRate ?? 1)
            heldRate = nil
        }
    }

    func unlockSpeed() {
        guard isSpeedLocked else { return }
        isSpeedLocked = false
        setRate(heldRate ?? 1)
        heldRate = nil
    }

    func retry() {
        observer.tearDown()
        observer.setPlayer(url: attachment.url, isGIF: isGIF, shouldLoop: isGIF ? true : nil)
        observer.setMuted(isMuted)
        layer.player = player
        player?.defaultRate = selectedRate
        observer.play()
    }

    func startPictureInPicture() {
        guard let pip, pip.isPictureInPicturePossible, Self.docked == nil else { return }
        pipFailed = false
        pip.startPictureInPicture()
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard playbackToken != nil else { return }
        restored = false
        Self.docked = self
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard Self.docked === self, let token = playbackToken else { return }
        observer.setFullscreenLooping(false)
        MediaPlaybackPresentation.shared.dock(token, url: attachment.url)
        if let host { host.close() } else { dismissRoute?() }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        guard playbackToken != nil else { return }
        clearDock()
        pipFailed = true
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler complete: @escaping (Bool) -> Void) {
        restore(complete)
    }

    func returnToFullscreen() {
        restore { [weak self] success in
            if success { self?.pip?.stopPictureInPicture() }
        }
    }

    private func restore(_ complete: @escaping (Bool) -> Void) {
        guard Self.docked === self else { complete(false); return }
        if let host, host.isBeingDismissed, let transition = host.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { complete(false); return }
                self.restore(complete)
            }
            return
        }
        if let host, host.presentingViewController != nil {
            restored = true
            complete(true)
            return
        }
        guard let presenter = UIApplication.shared.moroTopViewController() else { complete(false); return }
        restored = true
        NativeVideoPlayer.show(self, from: presenter) { complete(true) }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        guard Self.docked === self else { return }
        clearDock()
        if !restored { end() }
    }

    func leftFullscreen() {
        dismissRoute = nil
        if Self.docked !== self { end() }
    }

    private func clearDock() {
        guard Self.docked === self else { return }
        Self.docked = nil
        if let playbackToken { MediaPlaybackPresentation.shared.undock(playbackToken) }
    }

    func end() {
        guard let token = playbackToken else { return }
        playbackToken = nil
        clearDock()
        pip?.delegate = nil
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        possibleObservation = nil
        pip = nil
        layer.player = nil
        player?.defaultRate = 1
        observer.setMuted(true)
        if holdsAudioFocus { VideoAudioSession.endAudiblePlayback() }
        observer.tearDown()
        MediaPlaybackPresentation.shared.end(token)
    }

    nonisolated deinit {
        // A presentation interrupted before appearing still owns the pool and audio tokens.
        guard let token = playbackToken else { return }
        let observer = observer
        let hasFocus = holdsAudioFocus
        Task { @MainActor in
            observer.getPlayer()?.defaultRate = 1
            observer.setMuted(true)
            if hasFocus { VideoAudioSession.endAudiblePlayback() }
            observer.tearDown()
            MediaPlaybackPresentation.shared.end(token)
        }
    }
}
