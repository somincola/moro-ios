//
//  ImagePreviewView.swift
//  moro
//
//  Fullscreen image preview with swipe navigation and ALT text display at bottom.
//

import SDWebImage
import SwiftUI

struct ImagePreviewView: View {
    let attachments: [Status.Attachment]
    let initialIndex: Int
    var onDismiss: (() -> Void)? = nil

    @State private var currentIndex: Int
    @State private var showingAltTextSheet = false
    @State private var imageScales: [Int: CGFloat] = [:]
    @State private var dismissDragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    init(attachments: [Status.Attachment], initialIndex: Int = 0, onDismiss: (() -> Void)? = nil) {
        self.attachments = attachments
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    private var normalizedCurrentIndex: Int {
        guard !attachments.isEmpty else { return 0 }
        return min(max(currentIndex, 0), attachments.count - 1)
    }

    private var currentAttachment: Status.Attachment? {
        guard !attachments.isEmpty else { return nil }
        return attachments[normalizedCurrentIndex]
    }

    private var currentImageIsZoomed: Bool {
        (imageScales[normalizedCurrentIndex] ?? 1.0) > 1.01
    }

    private var dismissDragProgress: CGFloat {
        min(max(dismissDragOffset, 0) / 220, 1)
    }

    private var currentAltText: String? {
        guard let raw = currentAttachment?.description else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(Double(1 - (dismissDragProgress * 0.45)))
                .ignoresSafeArea()

            ZStack {
                if attachments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .moroScaledFont(size: 44, weight: .regular)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(MoroL10n.ImagePreview.emptyState)
                            .moroScaledFont(size: 15, weight: .medium)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                            ZoomableImageView(
                                url: attachment.url,
                                onScaleChanged: { scale in
                                    imageScales[index] = scale
                                }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))
                    .ignoresSafeArea()
                }

                VStack {
                    HStack {
                        MoroFloatingNavButton(kind: .close) {
                            closePreview()
                        }

                        Spacer()

                        if attachments.count > 1 {
                            Text("\(normalizedCurrentIndex + 1) / \(attachments.count)")
                                .moroScaledFont(size: 15, weight: .medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    altSummaryPanel
                }
            }
            .offset(y: max(dismissDragOffset, 0))
            .scaleEffect(1 - (dismissDragProgress * 0.06), anchor: .center)
            .animation(.easeOut(duration: 0.2), value: dismissDragOffset)
        }
        .statusBar(hidden: true)
        .simultaneousGesture(verticalDismissGesture)
        .onChange(of: currentIndex) { _, _ in
            dismissDragOffset = 0
        }
        .sheet(isPresented: $showingAltTextSheet) {
            if let currentAltText {
                AltTextOverlay(
                    altText: currentAltText,
                    onDismiss: { showingAltTextSheet = false }
                )
                .moroSheetSurface(detents: [.medium, .large])
            }
        }
    }

    private var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !currentImageIsZoomed else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissDragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                guard !currentImageIsZoomed else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dismissDragOffset = 0
                    }
                    return
                }
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dismissDragOffset = 0
                    }
                    return
                }

                let shouldDismiss =
                    value.translation.height > 120 || value.predictedEndTranslation.height > 170

                if shouldDismiss {
                    closePreview()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dismissDragOffset = 0
                    }
                }
            }
    }

    private func closePreview() {
        dismiss()
        onDismiss?()
    }

    private var altSummaryPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.below.photo")
                .moroScaledFont(size: 14, weight: .semibold)
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: 4) {
                Text(MoroL10n.ImagePreview.altBadge)
                    .moroScaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.65))

                Text(currentAltText ?? MoroL10n.ImagePreview.noAltDescription)
                    .moroScaledFont(size: 14)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if currentAltText != nil {
                Button {
                    showingAltTextSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .moroScaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.ImagePreview.altAccessibility)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 78, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color.black.opacity(0.78)],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let url: URL
    var onScaleChanged: ((CGFloat) -> Void)? = nil

    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    imageContent(image, in: proxy.size)
                } else if didFail {
                    failureView
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: url) {
                // SDWebImage handles the download, disk/memory cache and decode off the
                // main thread, and downsamples to ~screen size (capped) so a
                // high-megapixel original never becomes a giant in-memory bitmap that
                // freezes the main thread on render. Loaded once per URL and cached, so
                // re-opening / swiping is instant.
                let longestEdge = max(proxy.size.width, proxy.size.height)
                // Cap at ~the screen's own pixel count. At 1x viewing the display can't
                // show more pixels than this anyway, so the picture looks identical to
                // the original while never decoding a multi-megapixel bitmap the screen
                // can't render (the freeze + memory cause). 2000px keeps even the
                // simulator's software pipeline responsive.
                let maxPixel = min(max(longestEdge * displayScale, 512), 2000)
                let thumbnail = NSValue(cgSize: CGSize(width: maxPixel, height: maxPixel))
                let loaded: UIImage? = await withCheckedContinuation { continuation in
                    SDWebImageManager.shared.loadImage(
                        with: url,
                        options: [.retryFailed],
                        context: [.imageThumbnailPixelSize: thumbnail],
                        progress: nil
                    ) { downloaded, _, _, _, _, _ in
                        continuation.resume(returning: downloaded)
                    }
                }
                if !Task.isCancelled {
                    image = loaded
                    didFail = (loaded == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func imageContent(_ uiImage: UIImage, in size: CGSize) -> some View {
        let base = Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(magnificationGesture)
            .onTapGesture(count: 2) { toggleZoom() }

        if scale > 1.01 {
            base.highPriorityGesture(panGesture)
        } else {
            base
        }
    }

    private var failureView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .moroScaledFont(size: 48)
                .foregroundStyle(.white.opacity(0.5))
            Text(MoroL10n.ImagePreview.loadFailed)
                .moroScaledFont(size: 15)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleZoom() {
        withAnimation {
            if scale > 1.0 {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
        onScaleChanged?(scale)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(lastScale * value, 1.0)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                // Notify the parent only when a gesture settles (used for the
                // swipe-to-dismiss decision); the old per-frame callback re-rendered
                // the entire pager on every pinch step.
                onScaleChanged?(scale)
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}
