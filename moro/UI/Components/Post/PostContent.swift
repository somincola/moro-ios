//
//  PostContent.swift
//  moro
//
//  Post content component (text, media, poll, link preview, quote)
//

import SwiftUI

fileprivate enum PostContentMetrics {
    static let emojiSize: CGFloat = 20
    static let quoteHeaderIconSize: CGFloat = 12
    static let quoteAvatarSize: CGFloat = 20
    static let quoteMetadataSpacing: CGFloat = 4
    static let quoteCardCornerRadius: CGFloat = 8
    static let quoteHintIconSize: CGFloat = 11
    static let quoteHintCornerRadius: CGFloat = 6
}

fileprivate struct QuoteHintItem: Hashable {
    let icon: String
    let title: String
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
    var textFont: Font? = nil // Optional custom font for text content
    var uiTextFont: UIFont? = nil // UIKit path for custom emoji rich text
    var contentLineSpacing: CGFloat = 4 // Line spacing for the body text (timeline density)
    var quoteStyle: QuoteStyle = .flat // Style for quote display
    var isQuoted: Bool = false // Whether this is a quoted/referenced post (for gray styling)

    @StateObject private var concealViewModel: ContentConcealViewModel
    @State private var isQuoteNoticeExpanded = false
    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        textFont: Font? = nil,
        uiTextFont: UIFont? = nil,
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
        self.textFont = textFont
        self.uiTextFont = uiTextFont
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
        ContentConcealView(viewModel: concealViewModel) {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                // Text content with clickable links (mentions, hashtags, URLs, emojis)
                LinkedTextView(
                    html: status.content,
                    mentions: status.mentions,
                    tags: status.tags,
                    emojis: status.emojis,
                    parsingOptions: .statusBody,
                    emojiSize: PostContentMetrics.emojiSize, // Emoji size
                    lineSpacing: contentLineSpacing,
                    fontOverride: textFont ?? .system(size: 16, weight: .regular),
                    uiFontOverride: uiTextFont ?? (textFont == nil ? timelineBodyUIFont : nil),
                    textColorOverride: textColor,
                    onMentionTap: onMentionTap,
                    onHashtagTap: onHashtagTap,
                    onLinkTap: onLinkTap
                )
                .fixedSize(horizontal: false, vertical: true)

                PostTranslationSection(
                    status: status,
                    apiClient: translationAPIClient,
                    viewModel: translationViewModel,
                    onMentionTap: onMentionTap,
                    onHashtagTap: onHashtagTap,
                    onLinkTap: onLinkTap
                )

                // Render an accepted quote only after the original author has
                // authorized it. Other states remain privacy-safe placeholders.
                if let quote = status.quote {
                    if let quotedStatus = quote.displayableStatus {
                        quoteView(quotedStatus, style: quoteStyle)
                    } else {
                        quotePlaceholderView(for: quote.state, style: quoteStyle)
                    }
                }

                // Attachments: Media > Poll > Link Preview Card (priority order)
                switch status.attachmentType {
                case .media:
                    MediaGridView(
                        attachments: status.mediaAttachments,
                        isSensitive: status.sensitive,
                        onImageTap: { attachment, _ in
                            onImageTap?(attachment.url)
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

    private var timelineBodyUIFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(
                ofSize: 16 * theme.fontScale,
                weight: .regular
            ),
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
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
                .padding(.horizontal, theme.spacing.s)
                .padding(.vertical, theme.spacing.xs)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: PostContentMetrics.quoteCardCornerRadius,
                        style: .continuous
                    )
                    .stroke(theme.colors.primary300.opacity(0.9), lineWidth: 1)
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
    
    @ViewBuilder
    private func quoteView(_ quote: Status, style: QuoteStyle) -> some View {
        if let onQuotedStatusTap {
            Button(action: { onQuotedStatusTap(quote.displayStatus) }) {
                quoteBodyView(quote, style: style)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroL10n.Post.openQuotedPost(quote.account.displayNameFormatted))
        } else {
            quoteBodyView(quote, style: style)
        }
    }

    @ViewBuilder
    private func quoteBodyView(_ quote: Status, style: QuoteStyle) -> some View {
        let quoteText = quotePreviewText(for: quote)
        let quoteHintItems = quoteHints(for: quote)

        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: "quote.bubble")
                    .moroScaledFont(size: PostContentMetrics.quoteHeaderIconSize, weight: .medium)
                Text(MoroL10n.Post.quotedPost)
                    .font(theme.typography.caption)
                Spacer(minLength: theme.spacing.xs)
                if onQuotedStatusTap != nil {
                    Image(systemName: "chevron.right")
                        .moroScaledFont(size: 11, weight: .semibold)
                }
            }
            .foregroundStyle(theme.colors.textSecondary)

            HStack(alignment: .top, spacing: theme.spacing.s) {
                MoroAvatar(
                    imageURL: quote.account.avatarAnimatedURL,
                    staticImageURL: quote.account.avatarURL,
                    initials: quote.account.displayNameInitials,
                    size: PostContentMetrics.quoteAvatarSize
                )

                VStack(alignment: .leading, spacing: PostContentMetrics.quoteMetadataSpacing) {
                    HStack(spacing: theme.spacing.xs) {
                        AccountDisplayNameView(
                            account: quote.account,
                            typography: .captionStrong,
                            textColor: theme.colors.textPrimary,
                            lineLimit: 1,
                            truncationMode: .tail
                        )

                        Text("@\(quote.account.acct.isEmpty ? quote.account.username : quote.account.acct)")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(DateFormatting.relativeString(for: quote.createdAt))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)

                    if !quoteText.isEmpty {
                        Text(quoteText)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(MoroL10n.Post.noTextContent)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                    }

                    if !quoteHintItems.isEmpty {
                        HStack(spacing: theme.spacing.xs) {
                            ForEach(quoteHintItems, id: \.self) { hint in
                                HStack(spacing: 3) {
                                    Image(systemName: hint.icon)
                                        .moroScaledFont(size: PostContentMetrics.quoteHintIconSize, weight: .medium)
                                    Text(hint.title)
                                        .font(theme.typography.caption)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(.horizontal, theme.spacing.xs)
                                .padding(.vertical, 2)
                                .background(theme.colors.surfaceBase)
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: PostContentMetrics.quoteHintCornerRadius,
                                        style: .continuous
                                    )
                                    .stroke(theme.colors.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: PostContentMetrics.quoteHintCornerRadius,
                                        style: .continuous
                                    ))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .applyQuoteStyle(style, theme: theme)
    }

    private func quotePreviewText(for quote: Status) -> String {
        HTMLParser.stripHTML(quote.content)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func quoteHints(for quote: Status) -> [QuoteHintItem] {
        var hints: [QuoteHintItem] = []

        if !quote.mediaAttachments.isEmpty {
            let mediaCount = quote.mediaAttachments.count
            let mediaTitle = mediaCount == 1 ? "1 media item" : "\(mediaCount) media items"
            hints.append(QuoteHintItem(icon: "photo.on.rectangle", title: mediaTitle))
        }

        if let poll = quote.poll {
            let optionCount = poll.options.count
            let pollTitle = optionCount > 0 ? "\(optionCount)-option poll" : "Poll attached"
            hints.append(QuoteHintItem(icon: "chart.bar.xaxis", title: pollTitle))
        }

        return hints
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
        switch style {
        case .flat:
            self
                .padding(theme.spacing.s)
                .background(theme.colors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: PostContentMetrics.quoteCardCornerRadius, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: PostContentMetrics.quoteCardCornerRadius))
        case .card:
            self
                .padding(theme.spacing.m)
                .background(theme.colors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: PostContentMetrics.quoteCardCornerRadius, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: PostContentMetrics.quoteCardCornerRadius))
        }
    }
}
