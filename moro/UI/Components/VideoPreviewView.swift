//
//  VideoPreviewView.swift
//  moro
//
//  Video/GIF preview component for timeline display.
//  Shows preview image with play button, taps open fullscreen player.
//

import SwiftUI
import AVKit

struct VideoPreviewView: View {
    let attachment: Status.Attachment
    let isSensitive: Bool
    var onTap: (() -> Void)? = nil
    
    @Environment(\.moroTheme) private var theme
    @State private var isRevealed = false
    @Environment(\.moroMediaPrefs) private var mediaPrefs

    private var isConcealed: Bool {
        mediaPrefs.concealsMedia(markedSensitive: isSensitive) && !isRevealed
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Preview image (blurhash or preview URL)
                previewImage
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: isConcealed ? 25 : 0)
                
                // Play button overlay (always visible for video/GIF)
                playButtonOverlay
                
                // Sensitive content overlay
                if isConcealed {
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(MoroL10n.A11y.videoPlayer))
            .accessibilityAddTraits(.isButton)
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
                Image(systemName: attachment.type == "gifv" ? "photo.fill" : "video.fill")
                    .moroScaledFont(size: 32)
                    .foregroundStyle(theme.colors.textSecondary)
            )
    }
    
    // MARK: - Play Button Overlay
    
    private var playButtonOverlay: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 60, height: 60)
            
            // Play icon
            Image(systemName: attachment.type == "gifv" ? "play.circle.fill" : "play.fill")
                .moroScaledFont(size: attachment.type == "gifv" ? 28 : 24)
                .foregroundStyle(.white)
                .offset(x: attachment.type == "gifv" ? 0 : 2) // Optical center adjustment
        }
    }
    
    // MARK: - Sensitive Content Overlay
    
    private var sensitiveOverlay: some View {
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
