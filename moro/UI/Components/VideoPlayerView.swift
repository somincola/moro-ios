//
//  VideoPlayerView.swift
//  moro
//
//  Video player component with autoplay control based on network and settings.
//  Uses VideoPlayerObserver for proper resource management.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let attachment: Status.Attachment
    let isSensitive: Bool
    var onTap: (() -> Void)? = nil
    
    @Environment(\.moroTheme) private var theme
    @StateObject private var settings = AppSettings.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var playerObserver = VideoPlayerObserver()
    @State private var showControls = true
    @State private var isRevealed = false
    @Environment(\.moroMediaPrefs) private var mediaPrefs

    private var isConcealed: Bool {
        mediaPrefs.concealsMedia(markedSensitive: isSensitive) && !isRevealed
    }
    
    // Check if autoplay should be enabled
    private var shouldAutoplay: Bool {
        if isGIF {
            // GIFV should follow the dedicated GIF autoplay preference.
            return settings.autoplayGIFs
        }
        return networkMonitor.shouldAutoplayVideo(autoplayMode: settings.videoAutoplayMode)
    }
    
    private var isGIF: Bool {
        attachment.type == "gifv"
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player or preview
                if !isConcealed {
                    videoContent
                } else {
                    // Sensitive content overlay
                    sensitiveOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if isConcealed {
                    isRevealed = true
                } else {
                    onTap?()
                }
            }
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                playerObserver.tearDown()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(MoroL10n.A11y.videoPlayer))
            .accessibilityValue(Text(playerObserver.playingState == .playing
                                     ? MoroL10n.A11y.playing
                                     : MoroL10n.A11y.paused))
            .accessibilityAddTraits(.isButton)
        }
    }
    
    // MARK: - Video Content
    
    @ViewBuilder
    private var videoContent: some View {
        if let player = playerObserver.getPlayer() {
            // Use custom AVPlayerLayerView instead of VideoPlayer to avoid status bar issues
            ZStack {
                AVPlayerLayerView(player: player, videoGravity: .resizeAspectFill)
                
                // Play button overlay when not playing
                if playerObserver.playingState == .paused && showControls {
                    playButtonOverlay
                }
            }
            .onAppear {
                if shouldAutoplay {
                    playerObserver.play()
                }
            }
            .onTapGesture {
                togglePlayback()
            }
        } else {
            // Preview image while loading
            previewImage
                .overlay(
                    // Loading indicator
                    ProgressView()
                        .tint(.white)
                )
        }
    }
    
    // MARK: - Preview Image
    
    @ViewBuilder
    private var previewImage: some View {
        CachedAsyncImage(url: attachment.previewURL, blurhash: attachment.blurhash) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            placeholderView
        }
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(theme.colors.surfaceSubtle)
            .overlay(
                Image(systemName: "video.fill")
                    .moroScaledFont(size: 32)
                    .foregroundStyle(theme.colors.textSecondary)
            )
    }
    
    // MARK: - Play Button Overlay
    
    private var playButtonOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 60, height: 60)
            
            Image(systemName: "play.fill")
                .moroScaledFont(size: 24)
                .foregroundStyle(.white)
                .offset(x: 2) // Optical center adjustment
        }
    }
    
    // MARK: - Sensitive Content Overlay
    
    private var sensitiveOverlay: some View {
        ZStack {
            // Blurred preview
            previewImage
                .blur(radius: 25)
            
            // Overlay content
            VStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .moroScaledFont(size: 32)
                    .foregroundStyle(.white)
                
                Text(mediaPrefs.concealLabel(markedSensitive: isSensitive))
                    .font(theme.typography.subtitle)
                    .foregroundStyle(.white)
                
                Text(MoroL10n.SensitiveMedia.tapToView)
                    .font(theme.typography.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer() {
        let videoURL = attachment.url
        playerObserver.setPlayer(url: videoURL, isGIF: isGIF)
    }
    
    // MARK: - Playback Control
    
    private func togglePlayback() {
        switch playerObserver.playingState {
        case .playing:
            playerObserver.pause()
        case .paused, .waitingToPlayAtSpecifiedRate:
            playerObserver.play()
        @unknown default:
            break
        }
        
        // Hide controls after a delay
        showControls = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if playerObserver.playingState == .playing {
                showControls = false
            }
        }
    }
}
