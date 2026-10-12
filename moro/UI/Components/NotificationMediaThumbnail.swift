//
//  NotificationMediaThumbnail.swift
//  moro
//
//  Lightweight media preview for notification rows.
//

import SwiftUI

struct NotificationMediaThumbnail: View {
    let attachments: [Status.Attachment]
    let isSensitive: Bool
    let size: CGFloat

    @Environment(\.moroTheme) private var theme
    @Environment(\.moroMediaPrefs) private var mediaPrefs

    private var attachment: Status.Attachment? { attachments.first }
    private var additionalCount: Int { max(attachments.count - 1, 0) }

    var body: some View {
        ZStack {
            thumbnailContent

            if mediaPrefs.concealsMedia(markedSensitive: isSensitive) {
                Color.black.opacity(0.52)
                Image(systemName: "eye.slash.fill")
                    .moroScaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white)
            } else if attachment?.type == "video" || attachment?.type == "gifv" {
                Image(systemName: "play.fill")
                    .moroScaledFont(size: 12, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }

            if additionalCount > 0 {
                Text("+\(additionalCount)")
                    .moroScaledFont(size: 10, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.68)))
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
        .background(theme.colors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let attachment {
            if attachment.type == "audio", attachment.previewURL == nil {
                mediaPlaceholder(systemName: "waveform")
            } else {
                MoroNetworkImage(
                    url: attachment.previewURL ?? attachment.url,
                    contentMode: .fill,
                    playAnimations: false
                )
                .frame(width: size, height: size)
                .clipped()
            }
        } else {
            mediaPlaceholder(systemName: "photo")
        }
    }

    private func mediaPlaceholder(systemName: String) -> some View {
        Image(systemName: systemName)
            .moroScaledFont(size: 22, weight: .medium)
            .foregroundStyle(theme.colors.textSecondary)
            .frame(width: size, height: size)
    }
}
