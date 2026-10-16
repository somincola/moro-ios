//
//  VideoFullscreenView.swift
//  moro
//
//  Fullscreen video/GIF player view.
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
    @State private var showControls = true
    
    private var isGIF: Bool {
        attachment.type == "gifv"
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            // Video player
            if let player = playerObserver.getPlayer() {
                VideoPlayer(player: player)
                    .onAppear {
                        // Auto-play when fullscreen
                        playerObserver.play()
                    }
                    .overlay(
                        // Controls overlay
                        Group {
                            if showControls {
                                controlsOverlay
                            }
                        }
                    )
                    .onTapGesture {
                        toggleControls()
                    }
            } else {
                // Loading state
                ProgressView()
                    .tint(.white)
            }
        }
        .statusBar(hidden: true) // Hide status bar in fullscreen
        .onAppear {
            setupPlayer()
            // Opened on purpose, so it plays with sound.
            playerObserver.setMuted(false)
            VideoAudioSession.beginAudiblePlayback()
        }
        .onDisappear {
            // Back in the timeline it plays silently again, and other audio resumes.
            playerObserver.setMuted(true)
            VideoAudioSession.endAudiblePlayback()
            playerObserver.tearDown()
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            // Top bar with close button
            HStack {
                MoroFloatingNavButton(kind: .close) {
                    dismiss()
                    onDismiss?()
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Bottom controls (play/pause for videos)
            if !isGIF {
                HStack {
                    Button(action: {
                        togglePlayback()
                    }) {
                        Image(systemName: playerObserver.playingState == .playing ? "pause.fill" : "play.fill")
                            .moroScaledFont(size: 24)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(Text(playerObserver.playingState == .playing
                                             ? MoroL10n.A11y.pause
                                             : MoroL10n.A11y.play))
                }
                .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer() {
        let videoURL = attachment.url
        playerObserver.setPlayer(url: videoURL, isGIF: isGIF)
    }
    
    // MARK: - Controls
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        
        // Auto-hide controls after 3 seconds
        if showControls {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if playerObserver.playingState == .playing {
                    showControls = false
                }
            }
        }
    }
    
    private func togglePlayback() {
        switch playerObserver.playingState {
        case .playing:
            playerObserver.pause()
        case .paused, .waitingToPlayAtSpecifiedRate:
            playerObserver.play()
        @unknown default:
            break
        }
    }
}

// Status.Attachment already conforms to Identifiable via its id property
