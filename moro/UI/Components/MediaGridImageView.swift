//
//  MediaGridImageView.swift
//  moro
//
//  Single image cell for media grid with sensitive content handling.
//  ALT text is shown in fullscreen preview, not on thumbnail.
//

import SwiftUI

struct MediaGridImageView: View {
    let attachment: Status.Attachment
    let isSensitive: Bool
    let transitionNamespace: Namespace.ID
    let contentMode: ContentMode
    var onTap: (() -> Void)? = nil

    @State private var isRevealed: Bool = false
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroMediaPrefs) private var mediaPrefs

    init(
        attachment: Status.Attachment,
        isSensitive: Bool,
        transitionNamespace: Namespace.ID,
        contentMode: ContentMode = .fill,
        onTap: (() -> Void)? = nil
    ) {
        self.attachment = attachment
        self.isSensitive = isSensitive
        self.transitionNamespace = transitionNamespace
        self.contentMode = contentMode
        self.onTap = onTap
    }

    /// Concealment follows the Media Display setting, so flipping it updates
    /// every visible cell without re-creating them.
    private var isConcealed: Bool {
        mediaPrefs.concealsMedia(markedSensitive: isSensitive) && !isRevealed
    }

    /// Determine if this attachment is a GIF
    private var isGIF: Bool {
        attachment.type == "gifv" || attachment.url.pathExtension.lowercased() == "gif"
            || attachment.url.absoluteString.lowercased().contains(".gif")
    }

    /// Get the appropriate image URL based on autoplay settings
    private var imageURL: URL? {
        if isGIF {
            // For GIFs, use preview URL (static) if autoplay is disabled
            return mediaPrefs.autoplayGIFs
                ? attachment.url : (attachment.previewURL ?? attachment.url)
        } else {
            // For regular images, always use preview URL if available
            return attachment.previewURL ?? attachment.url
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image content - constrained to geometry size
                Group {
                    if isGIF {
                        InlineGIFImageView(attachment: attachment, contentMode: contentMode,
                                           isConcealed: isConcealed)
                    } else {
                        MoroNetworkImage(url: imageURL, contentMode: contentMode, playAnimations: false)
                    }
                }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .blur(radius: isConcealed ? 25 : 0)

                // Sensitive content overlay
                if isConcealed {
                    sensitiveOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
            .contentShape(.contextMenuPreview, Rectangle())
            .contextMenu {
                // Concealed media gets no menu: the lifted preview would reveal it.
                if !isConcealed {
                    ForEach(MediaExportAction.allCases, id: \.self) { action in
                        Button {
                            Task { await perform(action) }
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                }
            }
            .accessibilityElement(children: isGIF ? .contain : .ignore)
            .accessibilityLabel(mediaAccessibilityLabel)
            .accessibilityAddTraits(onTap != nil ? [.isImage, .isButton] : .isImage)
        }
        // Zoom source for the UIKit-presented viewer; the matched source serves the fallback cover.
        .background(MediaPreviewSource(id: attachment.id))
        .matchedTransitionSource(id: attachment.id, in: transitionNamespace)
    }

    /// VoiceOver label: the attachment's alt text when present, otherwise a generic
    /// "Image", prefixed with "Sensitive content" while still concealed.
    private var mediaAccessibilityLabel: Text {
        let alt = attachment.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = alt.isEmpty ? MoroL10n.Media.accessibilityImage : alt
        if isConcealed {
            return Text("\(mediaPrefs.concealLabel(markedSensitive: isSensitive)), \(base)")
        }
        return Text(base)
    }

    // MARK: - Subviews

    private var loadingView: some View {
        Rectangle()
            .fill(theme.colors.surfaceSubtle)
            .overlay {
                ProgressView()
                    .tint(theme.colors.textSecondary)
            }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(theme.colors.surfaceSubtle)
            .overlay {
                Image(systemName: "photo")
                    .moroScaledFont(size: 24)
                    .foregroundStyle(theme.colors.textSecondary)
            }
    }

    private var sensitiveOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.5))

            VStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                    .moroScaledFont(size: 28, weight: .medium)
                    .foregroundStyle(.white)

                Text(mediaPrefs.concealLabel(markedSensitive: isSensitive))
                    .font(theme.typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Actions

    private func perform(_ action: MediaExportAction) async {
        do {
            if let message = try await action.perform(on: attachment.url) {
                AppFeedbackCenter.shared.showSuccess(message)
            }
        } catch {
            AppFeedbackCenter.shared.showError(MediaExportService.message(for: error))
        }
    }

    private func handleTap() {
        if isConcealed {
            withAnimation(.easeInOut(duration: 0.3)) {
                isRevealed = true
            }
        } else {
            onTap?()
        }
    }
}
