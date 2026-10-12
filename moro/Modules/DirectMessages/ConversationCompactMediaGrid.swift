//
//  ConversationCompactMediaGrid.swift
//  moro
//
//  Compact, bounded media presentation for direct-message bubbles.
//

import SwiftUI

struct ConversationCompactMediaGrid: View {
    let attachments: [Status.Attachment]
    let isSensitive: Bool

    @Environment(\.moroTheme) private var theme
    @State private var selectedImageAttachment: Status.Attachment?
    @State private var selectedImageIndex = 0
    @State private var selectedVideoAttachment: Status.Attachment?
    @State private var isSensitiveRevealed = false
    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Namespace private var mediaTransitionNamespace

    private let gridWidth: CGFloat = 208
    private let gridSpacing: CGFloat = 2

    init(attachments: [Status.Attachment], isSensitive: Bool) {
        self.attachments = attachments
        self.isSensitive = isSensitive
    }

    private var isConcealed: Bool {
        mediaPrefs.concealsMedia(markedSensitive: isSensitive) && !isSensitiveRevealed
    }

    private var supportedAttachments: [Status.Attachment] {
        attachments.filter {
            let type = $0.type.lowercased()
            return type == "image" || type == "video" || type == "gifv"
        }
    }

    private var displayedAttachments: [Status.Attachment] {
        Array(supportedAttachments.prefix(4))
    }

    private var imageAttachments: [Status.Attachment] {
        supportedAttachments.filter { $0.type.lowercased() == "image" }
    }

    private var gridHeight: CGFloat {
        switch displayedAttachments.count {
        case 0:
            return 0
        case 1:
            return 154
        case 2:
            return 116
        default:
            return 164
        }
    }

    var body: some View {
        if !displayedAttachments.isEmpty {
            gridLayout
                .frame(width: gridWidth, height: gridHeight)
                .background(theme.colors.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                }
                .fullScreenCover(item: $selectedImageAttachment) { attachment in
                    ImagePreviewView(
                        attachments: imageAttachments,
                        initialIndex: selectedImageIndex,
                        onDismiss: { selectedImageAttachment = nil }
                    )
                    .navigationTransition(
                        .zoom(sourceID: attachment.id, in: mediaTransitionNamespace)
                    )
                }
                .fullScreenCover(item: $selectedVideoAttachment) { attachment in
                    VideoFullscreenView(
                        attachment: attachment,
                        onDismiss: { selectedVideoAttachment = nil }
                    )
                }
        }
    }

    @ViewBuilder
    private var gridLayout: some View {
        GeometryReader { geometry in
            let columnWidth = (geometry.size.width - gridSpacing) / 2
            let rowHeight = (geometry.size.height - gridSpacing) / 2

            switch displayedAttachments.count {
            case 1:
                mediaCell(displayedAttachments[0], contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            case 2:
                HStack(spacing: gridSpacing) {
                    mediaCell(displayedAttachments[0], contentMode: .fill)
                        .frame(width: columnWidth, height: geometry.size.height)
                    mediaCell(displayedAttachments[1], contentMode: .fill)
                        .frame(width: columnWidth, height: geometry.size.height)
                }
            case 3:
                HStack(spacing: gridSpacing) {
                    mediaCell(displayedAttachments[0], contentMode: .fill)
                        .frame(width: columnWidth, height: geometry.size.height)

                    VStack(spacing: gridSpacing) {
                        mediaCell(displayedAttachments[1], contentMode: .fill)
                            .frame(width: columnWidth, height: rowHeight)
                        mediaCell(displayedAttachments[2], contentMode: .fill)
                            .frame(width: columnWidth, height: rowHeight)
                    }
                }
            default:
                VStack(spacing: gridSpacing) {
                    HStack(spacing: gridSpacing) {
                        mediaCell(displayedAttachments[0], contentMode: .fill)
                            .frame(width: columnWidth, height: rowHeight)
                        mediaCell(displayedAttachments[1], contentMode: .fill)
                            .frame(width: columnWidth, height: rowHeight)
                    }

                    HStack(spacing: gridSpacing) {
                        mediaCell(displayedAttachments[2], contentMode: .fill)
                            .frame(width: columnWidth, height: rowHeight)
                        mediaCell(displayedAttachments[3], contentMode: .fill)
                            .frame(width: columnWidth, height: rowHeight)
                    }
                }
            }
        }
    }

    private func mediaCell(
        _ attachment: Status.Attachment,
        contentMode: ContentMode
    ) -> some View {
        let isVideo = attachment.type.lowercased() == "video"
            || attachment.type.lowercased() == "gifv"
        let additionalCount = attachment.id == displayedAttachments.last?.id
            ? max(supportedAttachments.count - displayedAttachments.count, 0)
            : 0

        return ZStack {
            MoroNetworkImage(
                url: attachment.previewURL ?? attachment.url,
                contentMode: contentMode,
                playAnimations: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: isConcealed ? 22 : 0)

            if isConcealed {
                Color.black.opacity(0.5)

                Image(systemName: "eye.slash.fill")
                    .moroScaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(.white)
            } else if isVideo {
                Image(systemName: "play.fill")
                    .moroScaledFont(size: 13, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.56)))
            }

            if additionalCount > 0, !isConcealed {
                Text("+\(additionalCount)")
                    .font(theme.typography.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.68)))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(attachment)
        }
        .matchedTransitionSource(id: attachment.id, in: mediaTransitionNamespace)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: attachment))
        .accessibilityAddTraits(.isButton)
    }

    private func handleTap(_ attachment: Status.Attachment) {
        if isConcealed {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSensitiveRevealed = true
            }
            return
        }

        let type = attachment.type.lowercased()
        if type == "image" {
            guard let index = imageAttachments.firstIndex(where: { $0.id == attachment.id }) else {
                return
            }
            selectedImageIndex = index
            selectedImageAttachment = attachment
        } else {
            selectedVideoAttachment = attachment
        }
    }

    private func accessibilityLabel(for attachment: Status.Attachment) -> Text {
        if isConcealed {
            return Text(MoroL10n.SensitiveMedia.title)
        }

        let altText = attachment.description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !altText.isEmpty {
            return Text(altText)
        }

        let type = attachment.type.lowercased()
        return Text(type == "image" ? MoroL10n.Media.accessibilityImage : MoroL10n.A11y.videoPlayer)
    }
}
