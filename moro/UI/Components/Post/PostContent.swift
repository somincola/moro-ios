//
//  PostContent.swift
//  moro
//
//  Post content component (text, media, poll, link preview, quote)
//

import SwiftUI

fileprivate enum PostContentMetrics {
    static let quoteMetadataSpacing: CGFloat = 4
    static let quoteCardCornerRadius: CGFloat = 14
}

/// Post content component
struct PostContent: View {
    let status: Status
    var translationAPIClient: MastodonAPI? = nil
    let translationViewModel: StatusTranslationViewModel
    var onMentionTap: ((String, URL) -> Bool)? = nil
    var onHashtagTap: ((String, URL) -> Void)? = nil
    var onLinkTap: ((URL) -> Void)? = nil
    var onPollVote: ((String, [Int]) async -> Bool)? = nil
    var onQuotedStatusTap: ((Status) -> Void)? = nil
    var onImageTap: ((URL) -> Void)? = nil
    var mediaActions: PostActions
    var isFocused: Bool = false
    var contentLineSpacing: CGFloat = 4 // Line spacing for the body text (timeline density)
    var quoteStyle: QuoteStyle = .flat // Style for quote display
    var isQuoted: Bool = false // Whether this is a quoted/referenced post (for gray styling)

    @StateObject private var concealViewModel: ContentConcealViewModel
    @State private var isQuoteNoticeExpanded = false
    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.mediaPreviewHandlers) private var mediaPreviewHandlers
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(
        status: Status,
        translationAPIClient: MastodonAPI? = nil,
        translationViewModel: StatusTranslationViewModel,
        onMentionTap: ((String, URL) -> Bool)? = nil,
        onHashtagTap: ((String, URL) -> Void)? = nil,
        onLinkTap: ((URL) -> Void)? = nil,
        onPollVote: ((String, [Int]) async -> Bool)? = nil,
        onQuotedStatusTap: ((Status) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        mediaActions: PostActions = .empty,
        isFocused: Bool = false,
        contentLineSpacing: CGFloat = 4,
        quoteStyle: QuoteStyle = .flat,
        isQuoted: Bool = false
    ) {
        self.status = status
        self.translationAPIClient = translationAPIClient
        self.translationViewModel = translationViewModel
        self.onMentionTap = onMentionTap
        self.onHashtagTap = onHashtagTap
        self.onLinkTap = onLinkTap
        self.onPollVote = onPollVote
        self.onQuotedStatusTap = onQuotedStatusTap
        self.onImageTap = onImageTap
        self.mediaActions = mediaActions
        self.isFocused = isFocused
        self.contentLineSpacing = contentLineSpacing
        self.quoteStyle = quoteStyle
        self.isQuoted = isQuoted

        _concealViewModel = StateObject(
            wrappedValue: ContentConcealViewModel(
                statusID: status.id,
                hasContentWarning: status.spoilerText != nil && !status.spoilerText!.isEmpty,
                hasFilterWarning: status.hasFilterWarning,
                spoilerText: status.spoilerText,
                filterWarningText: status.filterWarningBannerText
            )
        )
    }

    var body: some View {
        let textColor = isQuoted ? theme.colors.textSecondary : theme.colors.textPrimary
        let bodyFont = theme.postUIFont(sizeAdjustment: isFocused ? 2 : 0)
        let lineSpacing = contentLineSpacing * bodyFont.pointSize / 16
        ContentConcealView(viewModel: concealViewModel) {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                // Text content with clickable links (mentions, hashtags, URLs, emojis)
                LinkedTextView(
                    html: status.content,
                    mentions: status.mentions,
                    tags: status.tags,
                    emojis: status.emojis,
                    parsingOptions: .statusBody,
                    emojiSize: InlineEmojiRendering.size(for: bodyFont),
                    // Post text is not selectable; "Copy text" in the ⋯ menu copies it.
                    isSelectable: false,
                    lineSpacing: lineSpacing,
                    fontOverride: Font(bodyFont),
                    uiFontOverride: bodyFont,
                    textColorOverride: textColor,
                    onMentionTap: onMentionTap,
                    onHashtagTap: onHashtagTap,
                    onLinkTap: onLinkTap
                )
                .environment(\.animatesPostEmoji, true)
                .fixedSize(horizontal: false, vertical: true)

                PostTranslationSection(
                    status: status,
                    apiClient: translationAPIClient,
                    viewModel: translationViewModel,
                    bodyFont: bodyFont,
                    lineSpacing: lineSpacing,
                    onMentionTap: onMentionTap,
                    onHashtagTap: onHashtagTap,
                    onLinkTap: onLinkTap
                )

                // Attachments: Media > Poll > Link Preview Card (priority order), placed before
                // the quoted post so the author's own media reads naturally with their text.
                switch status.attachmentType {
                case .media:
                    MediaGridView(
                        attachments: status.mediaAttachments,
                        isSensitive: status.sensitive,
                        onImageTap: { attachment, _ in
                            onImageTap?(attachment.url)
                        },
                        previewPost: {
                            let actions = mediaPreviewHandlers?.buildPostActions(for: status, prefetchRelationship: false) ?? mediaActions
                            return MediaPreviewPost(status: status, actions: actions, theme: theme, isFocused: isFocused)
                        }
                    )
                case .poll:
                    if let poll = status.poll {
                        PollView(poll: poll) { choices in
                            guard let onPollVote else { return false }
                            return await onPollVote(poll.id, choices)
                        }
                    }
                case .card:
                    if let card = status.card {
                        LinkPreviewCardView(card: card) {
                            if let handler = onLinkTap {
                                handler(card.url)
                            } else {
                                // URLHandler will be used in LinkPreviewCardView itself
                                openURL(card.url)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity) // Ensure card doesn't exceed container width and can shrink
                    }
                case .none:
                    EmptyView()
                }

                // Render an accepted quote only after the original author has
                // authorized it. Other states remain privacy-safe placeholders.
                if let quote = status.quote {
                    if let quotedStatus = quote.displayableStatus {
                        QuotedStatusCardView(
                            quote: quotedStatus,
                            style: quoteStyle,
                            onTap: onQuotedStatusTap,
                            onImageTap: onImageTap
                        )
                    } else {
                        quotePlaceholderView(for: quote.state, style: quoteStyle)
                    }
                }

                if let tags = status.tags, !tags.isEmpty {
                    PostTagStrip(tags: tags, onTagTap: onHashtagTap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading) // Ensure content doesn't exceed container width
        }
        .onAppear {
            syncConcealState()
        }
        .onChange(of: status.id) { _, _ in
            isQuoteNoticeExpanded = false
            syncConcealState()
        }
        .onChange(of: status.spoilerText) { _, _ in
            syncConcealState()
        }
        .onChange(of: status.hasFilterWarning) { _, _ in
            syncConcealState()
        }
        .onChange(of: status.filterWarningBannerText) { _, _ in
            syncConcealState()
        }
    }

    private func syncConcealState() {
        concealViewModel.sync(
            statusID: status.id,
            hasContentWarning: status.spoilerText != nil && !status.spoilerText!.isEmpty,
            hasFilterWarning: status.hasFilterWarning,
            spoilerText: status.spoilerText,
            filterWarningText: status.filterWarningBannerText
        )
    }

    // MARK: - Quote View
    
    enum QuoteStyle {
        case flat      // Flat style for timeline (no background)
        case card      // Card style for detail view (with background)
    }

    @ViewBuilder
    private func quotePlaceholderView(for state: Status.QuoteState, style: QuoteStyle) -> some View {
        if state == .pending {
            Button(action: toggleQuoteNotice) {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    HStack(spacing: theme.spacing.xs) {
                        Image(systemName: "clock")
                            .moroScaledFont(size: 11, weight: .regular)
                            .foregroundStyle(theme.colors.textPrimary)
                            .accessibilityHidden(true)

                        Text(MoroL10n.Post.quotePendingTitle)
                            .font(theme.typography.caption)
                            .fontWeight(.regular)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .layoutPriority(1)

                        Spacer(minLength: theme.spacing.xs)

                        HStack(spacing: 4) {
                            Text(MoroL10n.Post.quotePendingLearnMore)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Image(systemName: "chevron.down")
                                .moroScaledFont(size: 9, weight: .semibold)
                                .rotationEffect(.degrees(isQuoteNoticeExpanded ? 180 : 0))
                        }
                        .font(theme.typography.caption)
                        .fontWeight(.regular)
                        .foregroundStyle(theme.colors.textPrimary)
                    }

                    if isQuoteNoticeExpanded {
                        Text(MoroL10n.Post.quotePendingMessage)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -AnimationTokens.motion.sm)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(
                        cornerRadius: PostContentMetrics.quoteCardCornerRadius,
                        style: .continuous
                    )
                    .fill(theme.colors.surfaceSubtle)
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: PostContentMetrics.quoteCardCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(theme.colors.borderSubtle, lineWidth: 1)
                }
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: PostContentMetrics.quoteCardCornerRadius,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(QuoteNoticePressStyle(reduceMotion: accessibilityReduceMotion))
            .sensoryFeedback(.selection, trigger: isQuoteNoticeExpanded)
            .accessibilityLabel(MoroL10n.Post.quotePendingTitle)
            .accessibilityValue(
                isQuoteNoticeExpanded
                    ? MoroL10n.Post.quotePendingMessage
                    : MoroL10n.Post.quotePendingLearnMore
            )
        } else {
            HStack(alignment: .top, spacing: theme.spacing.s) {
                Image(systemName: "quote.bubble")
                    .moroScaledFont(size: 14, weight: .regular)
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: PostContentMetrics.quoteMetadataSpacing) {
                    Text(MoroL10n.Post.quoteUnavailableTitle)
                        .font(theme.typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.colors.textSecondary)

                    Text(MoroL10n.Post.quoteUnavailableMessage)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .applyQuoteStyle(style, theme: theme)
            .accessibilityElement(children: .combine)
        }
    }

    private func toggleQuoteNotice() {
        let update = {
            isQuoteNoticeExpanded.toggle()
        }

        if accessibilityReduceMotion {
            update()
        } else {
            withAnimation(AnimationTokens.easing.springSoft, update)
        }
    }
}

// MARK: - Quote Style Modifier

private struct QuoteNoticePressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AnimationTokens.duration.xs),
                value: configuration.isPressed
            )
    }
}

extension View {
    @ViewBuilder
    func applyQuoteStyle(_ style: PostContent.QuoteStyle, theme: MoroTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: PostContentMetrics.quoteCardCornerRadius, style: .continuous)
        switch style {
        case .flat:
            self
                .padding(12)
                .background(shape.fill(theme.colors.surfaceSubtle))
                .overlay(shape.strokeBorder(theme.colors.borderSubtle, lineWidth: 1))
                .clipShape(shape)
        case .card:
            self
                .padding(14)
                .background(shape.fill(theme.colors.surfaceSubtle))
                .overlay(shape.strokeBorder(theme.colors.borderSubtle, lineWidth: 1))
                .clipShape(shape)
        }
    }
}
