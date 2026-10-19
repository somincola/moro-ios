//
//  VideoPlayerView.swift
//  moro
//
//  Video player component with autoplay control based on network and settings.
//  Uses VideoPlayerObserver for proper resource management.
//
//  Playback rules:
//  • A video plays only while it is on screen (most of it visible) and the app is active;
//    scrolling it away, leaving the page or the app pauses it.
//  • Autoplay follows Settings: Always, Wi-Fi only, or Never. With autoplay off nothing is
//    downloaded until the viewer presses play.
//  • A video plays once and stops at the end; GIFs (gifv) loop, following the GIF setting.
//  • In the timeline videos play silently and never interrupt other audio; fullscreen
//    plays the sound. Low Power Mode and the system "Auto-Play Video Previews" /
//    "Auto-Play Animated Images" settings turn autoplay off.
//  • Tapping the video opens it in the system player; the play button plays it in place.
//  • A video that fails to load shows a retry button instead of loading forever.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let attachment: Status.Attachment
    let isSensitive: Bool
    /// `.fit` shows the whole video, with dark bars where its shape doesn't match the box.
    var contentMode: ContentMode = .fill
    var onTap: (() -> Void)? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettings.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    // Parks the player when the row scrolls away, so coming back is instant.
    @StateObject private var playerObserver = VideoPlayerObserver(pool: .shared)
    /// True once the player layer has a frame. Until then the poster stays on top, so a
    /// video never shows as an empty black box while it loads.
    @State private var isFrameReady = false
    @State private var isRevealed = false
    /// Most of the video is on screen.
    @State private var isVisible = false
    /// The viewer pressed play, so it plays even with autoplay off.
    @State private var playRequested = false
    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages

    /// How much of the video must be on screen for it to play.
    static let visibleFraction = 0.6

    private var isConcealed: Bool {
        mediaPrefs.concealsMedia(markedSensitive: isSensitive) && !isRevealed
    }

    // Check if autoplay should be enabled
    private var shouldAutoplay: Bool {
        // Low Power Mode: nothing starts on its own; play still works.
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        if isGIF {
            // GIFV follows the GIF preference and the system "Auto-Play Animated Images".
            return settings.autoplayGIFs && playAnimatedImages
        }
        // Videos follow the in-app setting and the system "Auto-Play Video Previews".
        return UIAccessibility.isVideoAutoplayEnabled
            && networkMonitor.shouldAutoplayVideo(autoplayMode: settings.videoAutoplayMode)
    }

    private var isGIF: Bool {
        attachment.type == "gifv"
    }

    private var isPlaying: Bool {
        playerObserver.playingState != .paused
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
                    updatePlayback()
                } else {
                    onTap?()
                }
            }
            .onScrollVisibilityChange(threshold: Self.visibleFraction) { visible in
                isVisible = visible
                updatePlayback()
            }
            .onChange(of: scenePhase) { _, _ in
                updatePlayback()
            }
            .onAppear {
                // Back from fullscreen or another page: carry on if still on screen.
                updatePlayback()
            }
            .onDisappear {
                isFrameReady = false
                playRequested = false
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
        ZStack {
            if contentMode == .fit {
                Color.black
            }

            // The poster (or its blurhash) is there from the first frame of the row.
            previewImage

            if let player = playerObserver.getPlayer() {
                // Use custom AVPlayerLayerView instead of VideoPlayer to avoid status bar issues
                AVPlayerLayerView(
                    player: player,
                    videoGravity: contentMode == .fit ? .resizeAspect : .resizeAspectFill
                ) { isReady in
                    isFrameReady = isReady
                }
                .opacity(isFrameReady ? 1 : 0)
                .allowsHitTesting(false)
            }

            if playerObserver.didFail {
                // Couldn't load (e.g. a timeout on a slow network): offer to try again
                // instead of spinning forever.
                Button(action: retry) {
                    overlayButton(systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(MoroL10n.Timeline.retry))
            } else if isPlaying && !isFrameReady {
                ProgressView()
                    .tint(.white)
            } else if !isPlaying {
                // Plays the video here; tapping anywhere else opens it fullscreen.
                Button(action: playInPlace) {
                    playButtonOverlay
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Playback

    private func retry() {
        // The failed player can't be reused; start a fresh one.
        isFrameReady = false
        playerObserver.tearDown()
        playInPlace()
    }

    private func playInPlace() {
        playRequested = true
        setupPlayer()
        VideoAudioSession.prepareForSilentPlayback()
        // A video that has ended starts again from the beginning.
        playerObserver.play()
    }

    /// Plays the video while it may (on screen, app active, revealed, and allowed by the
    /// autoplay setting or a press of play) and pauses it otherwise.
    private func updatePlayback() {
        guard isVisible, !isConcealed, scenePhase == .active else {
            playerObserver.pause()
            return
        }
        guard playRequested || shouldAutoplay else { return }
        setupPlayer()
        VideoAudioSession.prepareForSilentPlayback()
        // Never restart a video that already played to the end; that's for the play button.
        if !playerObserver.hasPlayedToEnd {
            playerObserver.play()
        }
    }

    // MARK: - Preview Image
    
    @ViewBuilder
    private var previewImage: some View {
        CachedAsyncImage(url: attachment.previewURL, blurhash: attachment.blurhash) { image in
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
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
        overlayButton(systemImage: "play.fill", opticalOffset: 2)
    }

    private func overlayButton(systemImage: String, opticalOffset: CGFloat = 0) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 60, height: 60)

            Image(systemName: systemImage)
                .moroScaledFont(size: 24)
                .foregroundStyle(.white)
                .offset(x: opticalOffset) // Optical center adjustment
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
        // Timeline playback is silent; fullscreen (possibly showing this same player) has
        // the sound.
        if !VideoAudioSession.isAudible {
            playerObserver.setMuted(true)
        }
    }
}
