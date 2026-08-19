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
        _isRevealed = State(initialValue: !isSensitive)
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
                MoroNetworkImage(
                    url: imageURL,
                    contentMode: contentMode,
                    playAnimations: isGIF && mediaPrefs.autoplayGIFs
                )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .blur(radius: (isSensitive && !isRevealed) ? 25 : 0)

                // GIF play indicator if autoplay is disabled
                if isGIF && !mediaPrefs.autoplayGIFs {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .moroScaledFont(size: 32)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.5)))
                                .padding(8)
                        }
                    }
                }

                // Sensitive content overlay
                if isSensitive && !isRevealed {
                    sensitiveOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mediaAccessibilityLabel)
            .accessibilityAddTraits(onTap != nil ? [.isImage, .isButton] : .isImage)
        }
        .matchedTransitionSource(id: attachment.id, in: transitionNamespace)
    }

    /// VoiceOver label: the attachment's alt text when present, otherwise a generic
    /// "Image", prefixed with "Sensitive content" while still concealed.
    private var mediaAccessibilityLabel: Text {
        let alt = attachment.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = alt.isEmpty ? MoroL10n.Media.accessibilityImage : alt
        if isSensitive && !isRevealed {
            return Text("\(MoroL10n.SensitiveMedia.title), \(base)")
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

                Text(MoroL10n.SensitiveMedia.title)
                    .font(theme.typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Actions

    private func handleTap() {
        if isSensitive && !isRevealed {
            withAnimation(.easeInOut(duration: 0.3)) {
                isRevealed = true
            }
        } else {
            onTap?()
        }
    }
}
