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

    static func present(url: URL, isGIF: Bool, attachment: Status.Attachment? = nil) {
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
        session.controller = controller
        // The controller keeps the session alive; when it goes away, so does the session.
        objc_setAssociatedObject(controller, &sessionKey, session, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        presenter.present(controller, animated: true) {
            if let attachment { session.installExportActions(for: attachment, on: controller) }
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
final class NativeVideoSession: NSObject, AVPlayerViewControllerDelegate, UIContextMenuInteractionDelegate {
    let observer: VideoPlayerObserver
    weak var controller: AVPlayerViewController?
    private var hasEnded = false
    private let playbackToken: UUID
    private let needsAudioFocus: Bool
    private var attachment: Status.Attachment?
    private weak var exportSourceView: UIView?
    private weak var exportOverlay: VideoExportOverlayView?
    private var exportTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(url: URL, isGIF: Bool) {
        let observer = VideoPlayerObserver(pool: .shared, continuesExistingPlayer: true)
        // Take the fullscreen lease before inline views react to the presentation.
        observer.setPlayer(url: url, isGIF: isGIF, shouldLoop: isGIF ? true : nil)
        self.observer = observer
        needsAudioFocus = !isGIF
        playbackToken = MediaPlaybackPresentation.shared.begin()
        super.init()
        // Opened on purpose, so it plays with sound.
        observer.setMuted(false)
        if needsAudioFocus { VideoAudioSession.beginAudiblePlayback() }
    }

    var player: AVPlayer? { observer.getPlayer() }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        // AVKit must stop owning the player before the inline row resumes it; otherwise a
        // late controller teardown can pause the same player after the handoff.
        controller?.player = nil
        exportTask?.cancel()
        noticeTask?.cancel()
        observer.setMuted(true)
        if needsAudioFocus { VideoAudioSession.endAudiblePlayback() }
        observer.tearDown()
        MediaPlaybackPresentation.shared.end(playbackToken)
    }

    func installExportActions(for attachment: Status.Attachment, on controller: AVPlayerViewController) {
        self.attachment = attachment
        controller.view.addInteraction(UIContextMenuInteraction(delegate: self))
        guard let host = controller.view else { return }
        let overlay = VideoExportOverlayView(frame: host.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(overlay)
        exportOverlay = overlay
        let share = UIButton(type: .system)
        share.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        share.tintColor = .white
        share.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        share.layer.cornerRadius = 22
        share.accessibilityLabel = MoroL10n.MediaExport.share
        share.accessibilityIdentifier = "videoPreview.share"
        share.addAction(UIAction { [weak self] _ in self?.run(.share) }, for: .touchUpInside)
        overlay.addSubview(share)
        overlay.shareButton = share
        exportSourceView = share
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                               configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let attachment else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: MediaExportAction.available(for: attachment).map { action in
                UIAction(title: action.title, image: UIImage(systemName: action.systemImage)) { [weak self] _ in
                    self?.run(action)
                }
            })
        }
    }

    private func run(_ action: MediaExportAction) {
        guard !hasEnded, exportTask == nil, let attachment else { return }
        exportTask = Task { [weak self] in
            guard let self else { return }
            defer { self.exportTask = nil }
            do {
                if let message = try await action.perform(on: attachment, sourceView: self.exportSourceView) {
                    self.showNotice(message)
                }
            } catch is CancellationError {
            } catch {
                self.showNotice(MediaExportService.message(for: error))
            }
        }
    }

    private func showNotice(_ message: String) {
        guard !hasEnded, let overlay = exportOverlay else { return }
        noticeTask?.cancel()
        overlay.subviews.filter { $0.accessibilityIdentifier == "videoPreview.notice" }.forEach { $0.removeFromSuperview() }
        let notice = UILabel()
        notice.text = message
        notice.textColor = .white
        notice.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        notice.textAlignment = .center
        notice.font = .preferredFont(forTextStyle: .subheadline)
        notice.numberOfLines = 0
        notice.accessibilityIdentifier = "videoPreview.notice"
        overlay.addSubview(notice)
        overlay.notice = notice
        overlay.setNeedsLayout()
        UIAccessibility.post(notification: .announcement, argument: message)
        noticeTask = Task { [weak notice] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            notice?.removeFromSuperview()
        }
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
        let token = playbackToken
        let needsAudioFocus = needsAudioFocus
        Task { @MainActor in
            observer.setMuted(true)
            if needsAudioFocus { VideoAudioSession.endAudiblePlayback() }
            observer.tearDown()
            MediaPlaybackPresentation.shared.end(token)
        }
    }
}

/// Installed above AVKit after presentation. Use the containing window's safe area, while
/// allowing every touch outside the export controls to reach the system playback controls.
private final class VideoExportOverlayView: UIView {
    // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
    nonisolated deinit {}

    weak var shareButton: UIButton?
    weak var notice: UILabel?

    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window else { return }
        let usable = convert(window.bounds.inset(by: window.safeAreaInsets), from: window)
        shareButton?.frame = CGRect(x: usable.maxX - 60, y: usable.minY + 12, width: 44, height: 44)
        if let notice {
            let size = notice.sizeThatFits(CGSize(width: max(1, usable.width - 80), height: .greatestFiniteMagnitude))
            let width = min(usable.width - 48, size.width + 32)
            let height = max(44, size.height + 20)
            notice.frame = CGRect(x: usable.midX - width / 2, y: usable.maxY - 100 - height, width: width, height: height)
        }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let target = super.hitTest(point, with: event)
        return target === self ? nil : target
    }
}
