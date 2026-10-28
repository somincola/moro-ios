//
//  NativeVideoPlayer.swift
//  moro
//
//  Opens a video in the system player (AVPlayerViewController): the standard close
//  button, scrubber, volume, AirPlay and swipe-down to dismiss. It continues the
//  player the timeline is already showing, so the frame and position carry over.
//

import AVKit
import ObjectiveC
import UIKit

@MainActor
enum NativeVideoPlayer {
    private static var sessionKey: UInt8 = 0

    static func present(url: URL, isGIF: Bool) {
        guard let presenter = topViewController(),
              !(presenter is AVPlayerViewController) else { return }

        let session = NativeVideoSession(url: url, isGIF: isGIF)
        guard let player = session.player else {
            session.end()
            return
        }

        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        // Picture in Picture needs a background audio mode the app doesn't have.
        controller.allowsPictureInPicturePlayback = false
        controller.modalPresentationStyle = .fullScreen
        controller.delegate = session
        // The controller keeps the session alive; when it goes away, so does the session.
        objc_setAssociatedObject(controller, &sessionKey, session, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        presenter.present(controller, animated: true) {
            session.observer.play()
        }
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.moroTopViewController()
    }
}

/// One fullscreen viewing: holds the shared player with sound on, and gives it back
/// (silent again, other audio resumed) when the player is closed.
@MainActor
final class NativeVideoSession: NSObject, AVPlayerViewControllerDelegate {
    let observer: VideoPlayerObserver
    private var hasEnded = false

    init(url: URL, isGIF: Bool) {
        observer = VideoPlayerObserver(pool: .shared, continuesExistingPlayer: true)
        super.init()
        observer.setPlayer(url: url, isGIF: isGIF)
        // Opened on purpose, so it plays with sound.
        observer.setMuted(false)
        VideoAudioSession.beginAudiblePlayback()
    }

    var player: AVPlayer? { observer.getPlayer() }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        observer.setMuted(true)
        VideoAudioSession.endAudiblePlayback()
        observer.tearDown()
    }

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard !context.isCancelled else { return }
            self?.end()
        }
    }

    deinit {
        // Closed some other way: still give the player back.
        guard !hasEnded else { return }
        let observer = self.observer
        Task { @MainActor in
            observer.setMuted(true)
            VideoAudioSession.endAudiblePlayback()
            observer.tearDown()
        }
    }
}
