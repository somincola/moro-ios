//
//  VideoFullscreenView.swift
//  moro
//
//  Fullscreen video/GIF page opened through the router (a media link). It uses the
//  system player controls; videos tapped in a post open the system player directly
//  (`NativeVideoPlayer`).
//

import SwiftUI
import AVKit

struct VideoFullscreenView: View {
    let attachment: Status.Attachment
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    // Continues the player the timeline row is already showing, so the video keeps its
    // frame and position instead of loading again from the start.
    @StateObject private var playerObserver = VideoPlayerObserver(pool: .shared, continuesExistingPlayer: true)

    private var isGIF: Bool {
        attachment.type == "gifv"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let player = playerObserver.getPlayer() {
                SystemVideoPlayerView(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            MoroFloatingNavButton(kind: .close) {
                dismiss()
                onDismiss?()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .statusBar(hidden: true) // Hide status bar in fullscreen
        .onAppear {
            playerObserver.setPlayer(url: attachment.url, isGIF: isGIF)
            // Opened on purpose, so it plays with sound.
            playerObserver.setMuted(false)
            if !isGIF { VideoAudioSession.beginAudiblePlayback() }
            playerObserver.play()
        }
        .onDisappear {
            // Back in the timeline it plays silently again, and other audio resumes.
            playerObserver.setMuted(true)
            if !isGIF { VideoAudioSession.endAudiblePlayback() }
            playerObserver.tearDown()
        }
    }
}

/// The system playback controls (scrubber, volume, AirPlay) around a player.
struct SystemVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        // Picture in Picture needs a background audio mode the app doesn't have.
        controller.allowsPictureInPicturePlayback = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player = nil
        coordinator.end()
    }

    @MainActor final class Coordinator {
        private let playbackToken = MediaPlaybackPresentation.shared.begin()
        func end() { MediaPlaybackPresentation.shared.end(playbackToken) }
        nonisolated deinit {
            let token = playbackToken
            Task { @MainActor in MediaPlaybackPresentation.shared.end(token) }
        }
    }
}
