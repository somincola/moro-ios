//
//  VideoPlayerView.swift
//  moro
//
//  Video player component with autoplay control based on network and settings.
//  Uses VideoPlayerObserver for proper resource management.
//
//  Playback rules:
//  • A video plays only while it is on screen (most of it visible) and the app is active;
//    scrolling it away or leaving the page releases it into a short bounded warm cache.
//  • Autoplay follows Settings: Always, Wi-Fi only, or Never. With autoplay off nothing is
//    downloaded until the viewer presses play.
//  • A video plays once. GIFV loops under autoplay; an explicit inline play runs once.
//  • In the timeline videos play silently and never interrupt other audio; fullscreen
//    video plays sound, while GIFV stays silent. Low Power Mode and the system "Auto-Play Video Previews" /
//    "Auto-Play Animated Images" settings turn autoplay off.
//  • Tapping the video opens it in the system player; the play button plays it in place.
//  • A video that fails to load shows a retry button instead of loading forever.
//

import SwiftUI
import AVKit
import Combine

struct VideoPlayerView: View {
    let attachment: Status.Attachment
    let isSensitive: Bool
    /// `.fit` shows the whole video, with dark bars where its shape doesn't match the box.
    var contentMode: ContentMode = .fill
    var onTap: (() -> Void)? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    // Preferences arrive through the environment, avoiding an AppSettings subscription per row.
    private var networkMonitor: NetworkMonitor { .shared }
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
    @State private var hasFinishedVideo = false
    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moroPlaybackScope) private var playbackScope
    private let presentation = MediaPlaybackPresentation.shared

    /// How much of the video must be on screen for it to play.
    static let visibleFraction = MediaPlaybackPolicy.visibleFraction

    private var isConcealed: Bool {
        mediaPrefs.concealsMedia(markedSensitive: isSensitive) && !isRevealed
    }

    // Check if autoplay should be enabled
    private var shouldAutoplay: Bool {
        // Low Power Mode: nothing starts on its own; play still works.
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        if isGIF {
            // GIFV follows the GIF preference and the system "Auto-Play Animated Images".
            return mediaPrefs.autoplayGIFs && playAnimatedImages && !reduceMotion
        }
        // Videos follow the in-app setting and the system "Auto-Play Video Previews".
        return UIAccessibility.isVideoAutoplayEnabled
            && networkMonitor.shouldAutoplayVideo(autoplayMode: mediaPrefs.videoAutoplayMode)
    }

    private var isGIF: Bool {
        attachment.type == "gifv"
    }

    private var isPlaying: Bool {
        playerObserver.isPlaybackActive
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
                }
            }
            .onScrollVisibilityChange(threshold: Self.visibleFraction) { visible in
                isVisible = visible
                if !visible { playRequested = false }
                updatePlayback()
            }
            .onChange(of: scenePhase) { _, _ in
                updatePlayback()
            }
            .onChange(of: playbackScope.isActive) { _, active in
                if !active { playRequested = false }
                updatePlayback()
            }
            .onChange(of: presentation.coversInlinePlayback) { _, covered in
                if covered {
                    if isGIF { playRequested = false }
                    isFrameReady = false
                    playerObserver.tearDown()
                } else {
                    updatePlayback()
                }
            }
            .onChange(of: mediaPrefs) { _, _ in updatePlayback() }
            .onChange(of: playAnimatedImages) { _, _ in updatePlayback() }
            .onChange(of: reduceMotion) { _, _ in updatePlayback() }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                updatePlayback()
            }
            .onChange(of: playerObserver.didReachEnd) { _, ended in
                if ended {
                    playRequested = false
                    if !isGIF { hasFinishedVideo = true }
                }
            }
            .onChange(of: attachment.url) { _, _ in
                hasFinishedVideo = false
                playRequested = false
                isFrameReady = false
                playerObserver.tearDown()
                updatePlayback()
            }
            .onReceive(networkMonitor.$networkType.dropFirst()) { _ in
                if !isGIF { updatePlayback() }
            }
            .onReceive(networkMonitor.$isConnected.dropFirst()) { _ in
                if !isGIF { updatePlayback() }
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
            .contentShape(.contextMenuPreview, Rectangle())
            .contextMenu {
                if !isConcealed {
                    ForEach(MediaExportAction.available(for: attachment), id: \.self) { action in
                        Button {
                            Task {
                                do {
                                    if let message = try await action.perform(on: attachment) {
                                        AppFeedbackCenter.shared.showSuccess(message)
                                    }
                                } catch {
                                    AppFeedbackCenter.shared.showError(MediaExportService.message(for: error))
                                }
                            }
                        } label: { Label(action.title, systemImage: action.systemImage) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(MoroL10n.A11y.videoPlayer))
            .accessibilityValue(Text(isPlaying
                                     ? MoroL10n.A11y.playing
                                     : MoroL10n.A11y.paused))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("media.video.\(attachment.id)")
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
                    // Keep the last displayed frame through a loop handoff or buffering;
                    // replacing it with the poster creates a visible jump on every replay.
                    if isReady { isFrameReady = true }
                }
                .opacity(isFrameReady ? 1 : 0)
                .allowsHitTesting(false)
            }

            // Keep opening the viewer and starting inline playback as separate accessible
            // controls. This button fills the media, underneath the smaller play/retry button.
            Button { onTap?() } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.A11y.videoPlayer)
                .accessibilityValue(isPlaying ? MoroL10n.A11y.playing : MoroL10n.A11y.paused)
                .accessibilityIdentifier("media.open.\(attachment.id)")

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
                .accessibilityLabel(MoroL10n.A11y.play)
                .accessibilityIdentifier("media.play.\(attachment.id)")
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
        guard !presentation.coversInlinePlayback else { return }
        playRequested = true
        hasFinishedVideo = false
        setupPlayer()
        VideoAudioSession.prepareForSilentPlayback()
        // A video that has ended starts again from the beginning.
        playerObserver.play()
    }

    /// Plays the video while it may (on screen, app active, revealed, and allowed by the
    /// autoplay setting or a press of play) and pauses it otherwise.
    private func updatePlayback() {
        guard !presentation.coversInlinePlayback else {
            playerObserver.tearDown()
            return
        }
        guard MediaPlaybackPolicy.canPlay(isVisible: isVisible, isActive: playbackScope.isActive,
            isSceneActive: scenePhase == .active, isCovered: false, isConcealed: isConcealed) else {
            isFrameReady = false
            playerObserver.tearDown()
            return
        }
        guard playRequested || shouldAutoplay else {
            isFrameReady = false
            playerObserver.tearDown()
            return
        }
        guard isGIF || !hasFinishedVideo else { return }
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
        playerObserver.setPlayer(url: videoURL, isGIF: isGIF, shouldLoop: isGIF && shouldAutoplay)
        // Timeline playback is silent; fullscreen (possibly showing this same player) has
        // the sound.
        if !VideoAudioSession.isAudible {
            playerObserver.setMuted(true)
        }
    }
}
