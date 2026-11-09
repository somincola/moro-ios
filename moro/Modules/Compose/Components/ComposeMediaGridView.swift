//
//  ComposeMediaGridView.swift
//  moro
//
//  Media grid view for compose screen with upload states and layout matching timeline posts.
//

import SwiftUI

struct ComposeMediaGridView: View {
    let attachments: [MediaAttachment]
    let onRemove: (String) -> Void
    let onEditAlt: (String) -> Void
    let onRetry: (String) -> Void
    var showsEditingControls = true
    
    @Environment(\.moroTheme) private var theme

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            gridLayout(for: attachments)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .clipped()
        }
    }
    
    @ViewBuilder
    private func gridLayout(for items: [MediaAttachment]) -> some View {
        switch items.count {
        case 1:
            singleItemLayout(items)
        case 2:
            twoItemLayout(items)
        case 3:
            threeItemLayout(items)
        case 4:
            fourPlusItemLayout(items)
        default:
            // Instances that allow more than 4 attachments: every tile stays visible so each
            // one can still be removed, retried or given ALT text (no "+N" overflow).
            manyItemLayout(items)
        }
    }

    @ViewBuilder
    private func manyItemLayout(_ items: [MediaAttachment]) -> some View {
        let columns = 3
        let rows = stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
        VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(rows[rowIndex]) { mediaTile($0) }
                    // Keep tiles the same width in a short last row.
                    ForEach(0..<(columns - rows[rowIndex].count), id: \.self) { _ in
                        Color.clear
                    }
                }
                .frame(height: 120)
            }
        }
    }
    
    // MARK: - Single Item Layout
    
    @ViewBuilder
    private func singleItemLayout(_ items: [MediaAttachment]) -> some View {
        mediaTile(items[0])
            .frame(height: 280)
    }
    
    // MARK: - Two Item Layout
    
    @ViewBuilder
    private func twoItemLayout(_ items: [MediaAttachment]) -> some View {
        HStack(spacing: 2) {
            mediaTile(items[0])
            
            mediaTile(items[1])
        }
        .frame(height: 200)
    }
    
    // MARK: - Three Item Layout
    
    @ViewBuilder
    private func threeItemLayout(_ items: [MediaAttachment]) -> some View {
        HStack(spacing: 2) {
            // Left: first item takes half width
            mediaTile(items[0])
            
            // Right: two items stacked
            VStack(spacing: 2) {
                mediaTile(items[1])
                
                mediaTile(items[2])
            }
        }
        .frame(height: 200)
    }
    
    // MARK: - Four+ Item Layout
    
    @ViewBuilder
    private func fourPlusItemLayout(_ items: [MediaAttachment]) -> some View {
        let displayedItems = Array(items.prefix(4))
        let hasMore = items.count > 4
        let moreCount = items.count - 4
        
        VStack(spacing: 2) {
            // First row: 2 items
            HStack(spacing: 2) {
                mediaTile(displayedItems[0])
                
                mediaTile(displayedItems[1])
            }
            
            // Second row: 2 items (with potential "more" overlay)
            HStack(spacing: 2) {
                if displayedItems.count > 2 {
                    mediaTile(displayedItems[2])
                }
                
                if displayedItems.count > 3 {
                    ZStack {
                        mediaTile(displayedItems[3])
                        
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

    private func mediaTile(_ attachment: MediaAttachment) -> some View {
        ComposeMediaTileView(
            attachment: attachment,
            showsEditingControls: showsEditingControls,
            onRemove: { onRemove(attachment.id) },
            onEditAlt: { onEditAlt(attachment.id) },
            onRetry: { onRetry(attachment.id) }
        )
        .id(attachment.id)
    }
}

// MARK: - Compose Media Tile View

private struct ComposeMediaTileView: View {
    let attachment: MediaAttachment
    let showsEditingControls: Bool
    let onRemove: () -> Void
    let onEditAlt: () -> Void
    let onRetry: () -> Void
    
    @Environment(\.moroTheme) private var theme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image content
                if case .uploaded = attachment.uploadState, attachment.url.scheme != "temp" {
                    CachedAsyncImage(url: attachment.previewURL ?? attachment.url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } placeholder: {
                        if let localPreview = attachment.previewImage {
                            Image(uiImage: localPreview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else {
                            placeholderView
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else if case .uploading = attachment.uploadState,
                    let previewImage = attachment.previewImage
                {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    // Show placeholder for uploading/failed states
                    placeholderView
                }
                
                // Upload state overlay
                uploadStateOverlay
                
                // Alt text is editable once the server attachment exists.
                if showsEditingControls, case .uploaded = attachment.uploadState {
                    altTextButtonOverlay
                }

                // Removal remains available while uploading and after failures so an
                // attachment can never trap the composer in a blocked state.
                if showsEditingControls { removeButtonOverlay }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
    
    // MARK: - Subviews
    
    private var placeholderView: some View {
        Rectangle()
            .fill(theme.colors.surfaceSubtle)
            .overlay {
                Image(systemName: "photo")
                    .moroScaledFont(size: 24)
                    .foregroundStyle(theme.colors.textSecondary)
            }
    }
    
    @ViewBuilder
    private var uploadStateOverlay: some View {
        switch attachment.uploadState {
        case .uploading(let progress):
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                
                VStack(spacing: theme.spacing.s) {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.2)
                    
                    Text(MoroL10n.ComposeMedia.uploading(Int(progress * 100)))
                        .font(theme.typography.caption)
                        .foregroundStyle(.white)
                }
            }
            
        case .failed:
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                
                VStack(spacing: theme.spacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .moroScaledFont(size: 24)
                        .foregroundStyle(.white)
                    
                    Text(MoroL10n.ComposeMedia.uploadFailed)
                        .font(theme.typography.caption)
                        .foregroundStyle(.white)

                    if showsEditingControls {
                        Button(action: onRetry) {
                            Text(MoroL10n.ComposeMedia.retry)
                                .font(theme.typography.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, theme.spacing.m)
                                .padding(.vertical, theme.spacing.s)
                                .background(
                                    Capsule()
                                        .fill(theme.colors.primary500)
                                )
                        }
                        .accessibilityIdentifier("compose.media.retry.\(attachment.id)")
                    }
                }
            }
            
        case .uploaded:
            EmptyView()
        }
    }
    
    private var removeButtonOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .moroScaledFont(size: 24)
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .frame(
                    width: MoroUtilityButtonMetrics.hitTargetSize,
                    height: MoroUtilityButtonMetrics.hitTargetSize
                )
                .contentShape(Rectangle())
                .padding(2)
                .accessibilityLabel(Text(MoroL10n.ComposeMedia.removeAttachment))
                .accessibilityIdentifier("compose.media.remove.\(attachment.id)")
            }

            Spacer()
        }
        .zIndex(2)
    }

    private var altTextButtonOverlay: some View {
        VStack {
            Spacer()

            HStack {
                Button(action: onEditAlt) {
                    HStack(spacing: 4) {
                        Image(systemName: attachment.description?.isEmpty == false ? "text.bubble.fill" : "text.bubble")
                            .moroScaledFont(size: 12)
                        Text(attachment.description?.isEmpty == false ? MoroL10n.ImagePreview.altBadge : MoroL10n.ComposeMedia.addAlt)
                            .font(theme.typography.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.6))
                    )
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityIdentifier("compose.media.alt.\(attachment.id)")
                
                Spacer()
            }
        }
        .zIndex(1)
    }
}
