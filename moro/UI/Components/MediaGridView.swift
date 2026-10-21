//
//  MediaGridView.swift
//  moro
//
//  Adaptive grid layout for media attachments.
//  Handles 1-4+ images with different layout strategies.
//

import SwiftUI

enum MediaGridLayoutMetrics {
    static let fallbackSingleImageAspectRatio: CGFloat = 3.0 / 2.0

    static func singleImageAspectRatio(for attachment: Status.Attachment) -> CGFloat {
        guard let rawRatio = attachment.previewAspectRatio else {
            return fallbackSingleImageAspectRatio
        }

        let ratio = CGFloat(rawRatio)
        return ratio.isFinite && ratio > 0 ? ratio : fallbackSingleImageAspectRatio
    }
}

struct MediaGridView: View {
    let attachments: [Status.Attachment]
    let isSensitive: Bool
    var onImageTap: ((Status.Attachment, Int) -> Void)? = nil
    
    @Environment(\.moroTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedAttachment: Status.Attachment? = nil
    @State private var selectedIndex: Int = 0
    @Namespace private var mediaTransitionNamespace
    
    // Filter to only image attachments (videos are not yet supported in grid view)
    private var imageAttachments: [Status.Attachment] {
        attachments.filter { $0.type == "image" }
    }
    
    // Filter video attachments (for future video support)
    private var videoAttachments: [Status.Attachment] {
        attachments.filter { $0.type == "video" || $0.type == "gifv" }
    }
    
    var body: some View {
        if imageAttachments.isEmpty && videoAttachments.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                // Show images in grid layout
                if !imageAttachments.isEmpty {
                    gridLayout
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .clipped()
                        .fullScreenCover(item: $selectedAttachment) { attachment in
                            ImagePreviewView(
                                attachments: imageAttachments,
                                initialIndex: selectedIndex,
                                onDismiss: { selectedAttachment = nil }
                            )
                            .navigationTransition(
                                .zoom(sourceID: attachment.id, in: mediaTransitionNamespace)
                            )
                        }
                }
                
                // Show videos/GIFs with autoplay support (using AVPlayerLayer to avoid status bar issues)
                if !videoAttachments.isEmpty {
                    videoLayout
                }
            }
        }
    }
    
    // MARK: - Video Layout
    
    @ViewBuilder
    private var videoLayout: some View {
        VStack(spacing: 8) {
            ForEach(videoAttachments, id: \.id) { attachment in
                // Like a single image: the video's own shape, capped in height. A capped
                // portrait video is shown whole with bars at the sides, never cropped.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(MediaGridLayoutMetrics.singleImageAspectRatio(for: attachment), contentMode: .fit)
                    .frame(minHeight: 64, maxHeight: maximumSingleImageHeight)
                    .overlay {
                        VideoPlayerView(
                            attachment: attachment,
                            isSensitive: isSensitive,
                            contentMode: .fit,
                            onTap: {
                                // The system player, continuing this player.
                                NativeVideoPlayer.present(url: attachment.url, isGIF: attachment.type == "gifv")
                            }
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    @ViewBuilder
    private var gridLayout: some View {
        let count = imageAttachments.count
        
        switch count {
        case 1:
            singleImageLayout
        case 2:
            twoImageLayout
        case 3:
            threeImageLayout
        default:
            fourPlusImageLayout
        }
    }
    
    // MARK: - Single Image Layout

    /// A standalone image follows the ratio of the preview that is actually rendered.
    /// Unlike a multi-image grid, it is not cropped into a fixed gallery ratio.
    private var singleImageAspectRatio: CGFloat {
        MediaGridLayoutMetrics.singleImageAspectRatio(for: imageAttachments[0])
    }

    /// Keep extreme portrait media from occupying several screens. Since the image
    /// uses aspect-fit, this caps only the container height and never crops the image.
    private var maximumSingleImageHeight: CGFloat {
        horizontalSizeClass == .regular ? 566 : 460
    }

    @ViewBuilder
    private var singleImageLayout: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(singleImageAspectRatio, contentMode: .fit)
            .frame(minHeight: 64, maxHeight: maximumSingleImageHeight)
            .overlay {
                imageCell(at: 0, contentMode: .fit)
                    .background(theme.colors.surfaceSubtle)
            }
    }
    
    // MARK: - Two Images Layout
    
    @ViewBuilder
    private var twoImageLayout: some View {
        HStack(spacing: 2) {
            imageCell(at: 0)
            imageCell(at: 1)
        }
        .frame(height: 200)
    }
    
    // MARK: - Three Images Layout
    
    @ViewBuilder
    private var threeImageLayout: some View {
        HStack(spacing: 2) {
            // Left: first image takes half width
            imageCell(at: 0)
            
            // Right: two images stacked
            VStack(spacing: 2) {
                imageCell(at: 1)
                imageCell(at: 2)
            }
        }
        .frame(height: 200)
    }
    
    // MARK: - Four+ Images Layout
    
    @ViewBuilder
    private var fourPlusImageLayout: some View {
        let hasMore = imageAttachments.count > 4
        let moreCount = imageAttachments.count - 4
        
        VStack(spacing: 2) {
            // First row: 2 images
            HStack(spacing: 2) {
                imageCell(at: 0)
                imageCell(at: 1)
            }
            
            // Second row: 2 images (with potential "more" overlay)
            HStack(spacing: 2) {
                if imageAttachments.count > 2 {
                    imageCell(at: 2)
                }
                
                if imageAttachments.count > 3 {
                    ZStack {
                        imageCell(at: 3)
                        
                        // "More" overlay if there are additional images
                        if hasMore {
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                            
                            Text("+\(moreCount)")
                                .moroScaledFont(size: 28, weight: .bold)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .frame(height: 280)
    }
    
    // MARK: - Actions

    private func imageCell(
        at index: Int,
        contentMode: ContentMode = .fill
    ) -> some View {
        MediaGridImageView(
            attachment: imageAttachments[index],
            isSensitive: isSensitive,
            transitionNamespace: mediaTransitionNamespace,
            contentMode: contentMode,
            onTap: { openPreview(index: index) }
        )
    }
    
    private func openPreview(index: Int) {
        let attachment = imageAttachments[index]
        // Presented from UIKit so rotating cannot close it by unloading this post's row.
        if MediaPreviewPresenter.present(attachments: imageAttachments, initialIndex: index,
            sourceID: attachment.id, theme: theme, dynamicTypeSize: dynamicTypeSize) { return }
        selectedIndex = index
        selectedAttachment = attachment
    }

}

// Make Attachment identifiable for fullScreenCover
extension Status.Attachment: Equatable {
    static func == (lhs: Status.Attachment, rhs: Status.Attachment) -> Bool {
        lhs.id == rhs.id
    }
}
