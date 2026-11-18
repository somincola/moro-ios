import SwiftUI

struct ProfileMediaGallery: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isNarrow = false

    let statuses: [Status]
    let onOpenPost: (Status) -> Void

    var body: some View {
        let spacing = theme.spacing.xs
        let columns = isNarrow || dynamicTypeSize.isAccessibilitySize ? 2 : 3

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
            ForEach(statuses) { status in
                let attachments = status.displayStatus.mediaAttachments
                if let cover = attachments.first(where: { ["image", "video", "gifv"].contains($0.type) }) ?? attachments.first {
                    ProfileMediaGalleryTile(status: status.displayStatus, cover: cover) { onOpenPost(status) }
                }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width < 330
        } action: { isNarrow = $0 }
        .padding(spacing)
    }
}

private struct ProfileMediaGalleryTile: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroMediaPrefs) private var mediaPreferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let status: Status
    let cover: Status.Attachment
    let onOpenPost: () -> Void

    private let cornerRadius: CGFloat = 6
    private var sourceID: String { "profile.gallery.\(status.id).\(cover.id)" }
    private var isVideo: Bool { cover.type == "video" || cover.type == "gifv" }
    private var isGIF: Bool { cover.type == "gifv" || cover.url.pathExtension.lowercased() == "gif" }

    private var concealmentLabel: String? {
        if status.hasFilterWarning { return MoroL10n.SensitiveMedia.filtered }
        if !mediaPreferences.expandContentWarnings, status.spoilerText?.isEmpty == false {
            return MoroL10n.SensitiveMedia.contentWarning
        }
        if mediaPreferences.concealsMedia(markedSensitive: status.sensitive) {
            return mediaPreferences.concealLabel(markedSensitive: status.sensitive)
        }
        return nil
    }

    var body: some View {
        let warning = concealmentLabel
        let count = status.mediaAttachments.count

        Button {
            if warning != nil {
                onOpenPost()
            } else {
                openMedia()
            }
        } label: {
            theme.colors.surfaceSubtle
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let warning {
                        VStack(spacing: theme.spacing.xs) {
                            Image(systemName: "eye.slash")
                            Text(warning)
                                .font(.caption2.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(theme.spacing.xs)
                    } else {
                        thumbnail
                    }
                }
                .clipShape(.rect(cornerRadius: cornerRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpenPost) {
                Label(MoroL10n.Profile.viewOriginalPost, systemImage: "text.bubble")
            }
        }
        .accessibilityLabel(warning ?? mediaLabel)
        .accessibilityValue(warning == nil && count > 1 ? MoroL10n.Search.mediaCount(count) : "")
        .accessibilityAction(named: Text(MoroL10n.Profile.viewOriginalPost), onOpenPost)
        .accessibilityIdentifier("profile.media.tile.\(status.id)")
    }

    private var thumbnail: some View {
        Group {
            if let url = cover.previewURL, cover.type == "image" || isVideo {
                MoroNetworkImage(url: url, contentMode: .fill, playAnimations: false)
            } else {
                Image(systemName: cover.type == "audio" ? "waveform" : "photo")
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if isGIF {
                badge { Text(verbatim: "GIF") }
            } else if isVideo {
                badge { Image(systemName: "play.fill") }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if status.mediaAttachments.count > 1 {
                badge {
                    HStack(spacing: 3) {
                        Image(systemName: "square.on.square")
                        Text(status.mediaAttachments.count, format: .number)
                    }
                }
            }
        }
        .background {
            if cover.type == "image" {
                MediaPreviewSource(id: sourceID, cornerRadius: cornerRadius)
            }
        }
    }

    private var mediaLabel: String {
        let type = if isGIF {
            "GIF"
        } else if isVideo {
            MoroL10n.A11y.videoPlayer
        } else if cover.type == "image" {
            MoroL10n.Media.accessibilityImage
        } else {
            MoroL10n.ProfileEditing.media
        }
        guard let alt = cover.description, !alt.isEmpty else { return type }
        return "\(type), \(alt)"
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.72), in: .capsule)
            .padding(theme.spacing.xs)
    }

    private func openMedia() {
        guard cover.url.scheme != "about" else { onOpenPost(); return }
        if isVideo {
            NativeVideoPlayer.present(url: cover.url, isGIF: isGIF, attachment: cover)
        } else if cover.type == "image" {
            let images = status.mediaAttachments.filter { $0.type == "image" }
            let index = images.firstIndex { $0.id == cover.id } ?? 0
            if !MediaPreviewPresenter.present(
                attachments: images, initialIndex: index, sourceID: sourceID,
                theme: theme, dynamicTypeSize: dynamicTypeSize
            ) {
                onOpenPost()
            }
        } else {
            onOpenPost()
        }
    }
}
