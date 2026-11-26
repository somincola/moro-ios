//
//  QuotedStatusCardView.swift
//  moro
//
//  Compact, X-inspired quoted post card with single-line author header,
//  left-aligned tappable media thumbnail (+N multi-image gallery preview),
//  and rich inline emoji body rendering.
//

import SwiftUI

struct QuotedStatusCardView: View {
    let quote: Status
    var style: PostContent.QuoteStyle = .flat
    var isInteractive: Bool = true
    var onTap: ((Status) -> Void)? = nil
    var onImageTap: ((URL) -> Void)? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Environment(\.mediaPreviewHandlers) private var mediaPreviewHandlers

    @State private var fallbackSelectedAttachment: Status.Attachment? = nil
    @State private var fallbackPreviewPost: MediaPreviewPost? = nil
    @State private var afterFallbackDismiss: (() -> Void)? = nil
    @Namespace private var quoteMediaNamespace

    private enum Metrics {
        static let cardCornerRadius: CGFloat = 14
        static let avatarSize: CGFloat = 20
        static let mediaThumbnailSize: CGFloat = 84
        static let mediaCornerRadius: CGFloat = 10
        static let contentSpacing: CGFloat = 8
        static let mediaTextSpacing: CGFloat = 10
    }

    private var quotedDisplayStatus: Status {
        quote.displayStatus
    }

    private var spoilerText: String? {
        let trimmed = quotedDisplayStatus.spoilerText?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var bodyElements: [ContentElement] {
        ContentParser.parseToElements(
            html: quotedDisplayStatus.content,
            mentions: quotedDisplayStatus.mentions,
            tags: quotedDisplayStatus.tags,
            emojis: quotedDisplayStatus.emojis,
            options: .statusBody
        )
        .compactedForQuoteCard
    }

    private var hasVisibleBodyText: Bool {
        !bodyElements.isEmpty
    }

    private var attachments: [Status.Attachment] {
        quotedDisplayStatus.mediaAttachments
    }

    private var imageAttachments: [Status.Attachment] {
        attachments.filter { $0.type == "image" }
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark ? theme.colors.surfaceElevated : theme.colors.surfaceBase
    }

    private var cardBorderColor: Color {
        if colorSchemeContrast == .increased {
            return theme.colors.textPrimary.opacity(0.32)
        }
        return colorScheme == .dark
            ? theme.colors.borderSubtle
            : theme.colors.textPrimary.opacity(0.11)
    }

    private var cardPadding: CGFloat {
        switch style {
        case .flat:
            return 12
        case .card:
            return 14
        }
    }

    var body: some View {
        let elements = bodyElements
        let bodyFont = theme.postUIFont(sizeAdjustment: -2)
        let emojiSize = InlineEmojiRendering.size(for: bodyFont)
        let cardShape = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            authorHeaderRow

            if let spoilerText {
                spoilerNoticeView(spoilerText)
            } else if !attachments.isEmpty {
                HStack(alignment: .top, spacing: Metrics.mediaTextSpacing) {
                    quotedMediaThumbnailButton(
                        attachments: attachments,
                        size: Metrics.mediaThumbnailSize
                    )

                    if !elements.isEmpty {
                        quotedBodyText(
                            elements: elements,
                            bodyFont: bodyFont,
                            emojiSize: emojiSize
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            } else if !elements.isEmpty {
                quotedBodyText(
                    elements: elements,
                    bodyFont: bodyFont,
                    emojiSize: emojiSize
                )
            } else if quotedDisplayStatus.poll == nil {
                Text(MoroL10n.Post.noTextContent)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            if let poll = quotedDisplayStatus.poll {
                pollHintRow(poll)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .background(cardShape.fill(cardBackgroundColor))
        .overlay {
            cardShape.strokeBorder(cardBorderColor, lineWidth: 1)
        }
        .clipShape(cardShape)
        .contentShape(cardShape)
        .allowsHitTesting(isInteractive)
        .onTapGesture {
            guard isInteractive else { return }
            onTap?(quotedDisplayStatus)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quote.card")
        .fullScreenCover(item: $fallbackSelectedAttachment, onDismiss: {
            let action = afterFallbackDismiss
            afterFallbackDismiss = nil
            fallbackPreviewPost = nil
            action?()
        }) { attachment in
            ImagePreviewView(
                attachments: imageAttachments.isEmpty ? [attachment] : imageAttachments,
                initialIndex: 0,
                post: fallbackPreviewPost,
                onDismiss: { fallbackSelectedAttachment = nil }
            )
            .navigationTransition(
                .zoom(sourceID: attachment.id, in: quoteMediaNamespace)
            )
        }
    }

    // MARK: - Author Header

    private var authorHeaderRow: some View {
        let account = quotedDisplayStatus.account
        let handle = account.acct.isEmpty ? account.username : account.acct

        return HStack(alignment: .center, spacing: 6) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials,
                seed: account.placeholderSeed,
                size: Metrics.avatarSize,
                allowsAnimation: false
            )

            AccountDisplayNameView(
                account: account,
                typography: .captionStrong,
                textColor: theme.colors.textPrimary,
                lineLimit: 1,
                fitsInlineWidth: true,
                truncationMode: .tail
            )
            .layoutPriority(2)

            Text("@\(handle)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Text("· \(DateFormatting.relativeString(for: quotedDisplayStatus.createdAt))")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MoroL10n.Post.openQuotedPost(account.displayNameFormatted))
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }

    // MARK: - Body Text

    @ViewBuilder
    private func quotedBodyText(
        elements: [ContentElement],
        bodyFont: UIFont,
        emojiSize: CGFloat
    ) -> some View {
        let style = InlineTextStyle(
            textColor: theme.colors.textPrimary,
            linkColor: theme.colors.contentLink,
            codeBackgroundColor: theme.colors.surfaceSubtle,
            codeFontSize: max(12, bodyFont.pointSize - 1),
            underlinesLinks: false,
            linksAreInteractive: false
        )
        let runs = InlineTextRunBuilder.runs(for: elements, style: style)
        let limit = dynamicTypeSize.isAccessibilitySize ? nil : 4

        InlineEmojiText(runs: runs, emojiSize: emojiSize)
            .font(Font(bodyFont))
            .foregroundStyle(theme.colors.textPrimary)
            .lineSpacing(2.5)
            .lineLimit(limit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
            .accessibilityLabel(elements.plainTextValue)
    }

    private func spoilerNoticeView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .moroScaledFont(size: 12, weight: .medium)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text(text)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Left Media Thumbnail

    private func quotedMediaThumbnailButton(
        attachments: [Status.Attachment],
        size: CGFloat
    ) -> some View {
        let first = attachments[0]
        let additionalCount = max(attachments.count - 1, 0)
        let conceals = mediaPrefs.concealsMedia(markedSensitive: quotedDisplayStatus.sensitive)
        let shape = RoundedRectangle(cornerRadius: Metrics.mediaCornerRadius, style: .continuous)

        return Button {
            openQuotedMedia(firstAttachment: first)
        } label: {
            ZStack {
                if first.type == "audio", first.previewURL == nil {
                    Image(systemName: "waveform")
                        .moroScaledFont(size: 22, weight: .medium)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: size, height: size)
                } else {
                    MoroNetworkImage(
                        url: first.previewURL ?? first.url,
                        contentMode: .fill,
                        playAnimations: false
                    )
                    .frame(width: size, height: size)
                    .clipped()
                }

                if conceals {
                    Color.black.opacity(0.56)
                    Image(systemName: "eye.slash.fill")
                        .moroScaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(.white)
                } else if first.type == "video" {
                    Image(systemName: "play.fill")
                        .moroScaledFont(size: 13, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.58)))
                } else if first.type == "gifv" {
                    Text("GIF")
                        .moroScaledFont(size: 10, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.black.opacity(0.68)))
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if additionalCount > 0 {
                    Text("+\(additionalCount)")
                        .moroScaledFont(size: 11, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: size, height: size)
            .background(theme.colors.surfaceSubtle)
            .background(MediaPreviewSource(id: first.id, cornerRadius: Metrics.mediaCornerRadius))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    theme.colors.textPrimary.opacity(colorScheme == .dark ? 0.14 : 0.08),
                    lineWidth: 0.5
                )
            }
            .matchedTransitionSource(id: first.id, in: quoteMediaNamespace)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MoroL10n.Post.quoteMediaCount(attachments.count))
        .accessibilityIdentifier("quote.mediaButton")
    }

    private func openQuotedMedia(firstAttachment: Status.Attachment) {
        let previewPost: MediaPreviewPost? = {
            let actions = mediaPreviewHandlers?.buildPostActions(
                for: quotedDisplayStatus,
                prefetchRelationship: false
            ) ?? .empty
            return MediaPreviewPost(
                status: quotedDisplayStatus,
                actions: actions,
                theme: theme,
                isFocused: false
            )
        }()

        if firstAttachment.type == "image" {
            let gallery = imageAttachments.isEmpty ? [firstAttachment] : imageAttachments
            onImageTap?(firstAttachment.url)
            if MediaPreviewPresenter.present(
                attachments: gallery,
                initialIndex: 0,
                sourceID: firstAttachment.id,
                theme: theme,
                dynamicTypeSize: dynamicTypeSize,
                post: previewPost
            ) {
                return
            }
            previewPost?.closeBeforeAction = { action in
                afterFallbackDismiss = action
                fallbackSelectedAttachment = nil
            }
            fallbackPreviewPost = previewPost
            fallbackSelectedAttachment = firstAttachment
        } else if firstAttachment.type == "video" || firstAttachment.type == "gifv" {
            NativeVideoPlayer.present(attachment: firstAttachment, post: previewPost)
        } else {
            onTap?(quotedDisplayStatus)
        }
    }

    // MARK: - Poll Hint

    private func pollHintRow(_ poll: Status.Poll) -> some View {
        let optionCount = poll.options.count
        let title = optionCount > 0
            ? MoroL10n.Post.quotePollOptions(optionCount)
            : MoroL10n.ComposeOriginal.badgePoll

        return HStack(spacing: 4) {
            Image(systemName: "chart.bar.xaxis")
                .moroScaledFont(size: 11, weight: .medium)
            Text(title)
                .font(theme.typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(theme.colors.textSecondary)
    }
}
